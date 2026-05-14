import json
import os
import re
import shutil
import uuid
from collections import Counter
from datetime import date, datetime, timedelta

# FFMPEG adresini Python'a zorla öğretiyoruz (faster-whisper için)
os.environ["PATH"] += os.pathsep + r"C:\ffmpeg\bin"

from faster_whisper import WhisperModel

from fastapi import Depends, FastAPI, File, Form, HTTPException, Query, UploadFile, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.security import OAuth2PasswordRequestForm
from pydantic import BaseModel
from sqlalchemy.orm import Session

from auth import create_access_token, get_current_user, get_password_hash, verify_password
from database import engine, get_db
import models
import schemas

# ── Chatbot: İstek şeması ─────────────────────────────────────────────────────
class ChatRequest(BaseModel):
    message: str

app = FastAPI(title="Voice To Action API", version="1.0.0")

# CORS: Güvenlik JWT üzerinden sağlanıyor; origin kısıtlaması prod'da yapılmalı.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# ── faster-whisper: Lazy Loading (sunucu başlarken RAM bloke etmez) ────────────
_WHISPER_MODEL: WhisperModel | None = None
# Yükleme başarısızsa hata mesajı burada saklanır; bir sonraki çağrıda
# tekrar indirilmeye çalışılmaz, direkt 503 döner.
_WHISPER_LOAD_ERROR: str | None = None

def _get_whisper_model() -> WhisperModel:
    """
    faster-whisper 'tiny' modelini ilk kullanımda güvenli şekilde yükler.
    Model indirilemiyor / bozuksa RuntimeError fırlatır ve hata kalıcı olarak
    _WHISPER_LOAD_ERROR'a yazılır; sonraki çağrılarda anında hata döner.
    """
    global _WHISPER_MODEL, _WHISPER_LOAD_ERROR

    # Daha önce başarısız olduysa tekrar deneme — anında hata dön.
    if _WHISPER_LOAD_ERROR is not None:
        raise RuntimeError(f"Whisper modeli yüklenemedi: {_WHISPER_LOAD_ERROR}")

    if _WHISPER_MODEL is None:
        try:
            print("[Whisper] faster-whisper 'base' modeli yükleniyor (CPU, int8)…")
            _WHISPER_MODEL = WhisperModel(
                "tiny",
                device="cpu",
                compute_type="int8",
                # Modeli gizli .cache yerine proje klasöründe görebileceğimiz
                # bir yere indir → kolayca silinip yeniden indirilebilir.
                download_root=os.path.join(BASE_DIR, "model_files"),
                # Bozuk/eksik yerel önbelleği atlayıp HuggingFace'den yeniden
                # indir; asla eski bozuk dosyayla takılmaz.
                local_files_only=False,
            )
            print("[Whisper] 'tiny' model hazır.")
        except Exception as exc:
            _WHISPER_LOAD_ERROR = str(exc)
            print(f"[Whisper] HATA — Model yüklenemedi: {exc}")
            raise RuntimeError(
                f"Whisper modeli yüklenemedi. "
                f"İnternet bağlantısını veya disk alanını kontrol edin. ({exc})"
            ) from exc

    return _WHISPER_MODEL


# ── Ses transkripsiyon yardımcısı: VAD filtreli (pydub'siz) ───────────────────
def _transcribe_audio(file_path: str) -> str:
    """
    Ses dosyasını faster-whisper ile metne çevirir.

    vad_filter=True  →  faster-whisper'ın dahili VAD (Ses Aktivite Algılama)
    motoru sessiz bölgeleri atlayarak her uzunluktaki sesi düşük RAM ile işler.
    Harici parçalama (pydub gibi) gerekmez; Python 3.14 ile tam uyumlu.
    """
    model = _get_whisper_model()
    print("[Whisper] Transkripsiyon başlatılıyor (VAD filtreli)…")
    segments, info = model.transcribe(
        file_path,
        language="tr",
        beam_size=5,
        vad_filter=True,
        vad_parameters=dict(
            min_silence_duration_ms=300,
            speech_pad_ms=200,
            threshold=0.5,
        ),
        no_speech_threshold=0.5,
        log_prob_threshold=-0.8,
        compression_ratio_threshold=2.2,
        condition_on_previous_text=False,
        temperature=0.0,
        word_timestamps=False,
        without_timestamps=False,
        initial_prompt="Bu bir Türkçe ders kaydıdır. Konuşmacı akademik içerik anlatmaktadır.",
    )

    segment_list = list(segments)

    # Düşük güvenilirlikli segmentleri filtrele
    filtered_segments = []
    for seg in segment_list:
        # avg_logprob çok düşükse (halüsinasyon) atla
        if hasattr(seg, 'avg_logprob') and seg.avg_logprob < -1.0:
            print(f"[Whisper] Düşük güven segmenti atlandı: {seg.text[:30]}")
            continue
        # no_speech_prob yüksekse atla
        if hasattr(seg, 'no_speech_prob') and seg.no_speech_prob > 0.7:
            print(f"[Whisper] Sessiz segment atlandı: {seg.text[:30]}")
            continue
        # Çok kısa ve anlamsız segmentleri atla
        if len(seg.text.strip()) < 3:
            continue
        # Tekrarlayan kelime artefaktı kontrolü
        seg_words = seg.text.strip().split()
        if len(seg_words) > 2:
            unique_ratio = len(set(seg_words)) / len(seg_words)
            if unique_ratio < 0.4:
                print(f"[Whisper] Tekrarlayan segment atlandı: {seg.text[:30]}")
                continue
        filtered_segments.append(seg)

    text = " ".join(seg.text.strip() for seg in filtered_segments).strip()

    # Post-processing: tekrarlayan cümleleri temizle
    sentences = text.split('. ')
    seen_sents = []
    unique_sentences = []
    for sent in sentences:
        sent_lower = sent.lower().strip()
        if len(sent_lower) < 5:
            continue
        # Bu cümleye çok benzer bir cümle var mı?
        is_dup = False
        for prev in seen_sents:
            prev_words = set(prev.split())
            curr_words = set(sent_lower.split())
            if prev_words and curr_words:
                jaccard = len(prev_words & curr_words) / len(prev_words | curr_words)
                if jaccard > 0.7:
                    is_dup = True
                    break
        if not is_dup:
            seen_sents.append(sent_lower)
            unique_sentences.append(sent)

    text = '. '.join(unique_sentences).strip()

    print(f"[Whisper] Tamamlandı. Dil: {info.language} | Metin: {len(text)} karakter")
    return text

# ---------------------------------------------------------------------------
# NLP: Türkçe kural tabanlı görev & hatırlatma çıkarıcı  (v4 – Hatırlatma Desteği)
# ---------------------------------------------------------------------------

# ── Hatırlatma: etkinlik kelimeleri ────────────────────────────────────────
# "haftaya sınav var", "yarın ders var", "veri yapıları çıkacak sınavda"
# gibi cümleler aksiyon fiili içermez ama önemli hatırlatmalardır.
_REMINDER_EVENT_WORDS: set[str] = {
    "sınav", "sınavı", "sınavda", "sınavına",
    "ders", "dersi", "dersimiz", "derste",
    "ödev", "ödevi", "ödevimiz",
    "sunum", "sunumu",
    "teslim", "teslimi",
    "toplantı", "toplantısı",
    "proje", "projesi",
    "vize", "final", "quiz", "bütünleme",
    "seminer", "konferans", "workshop",
    "randevu", "randevusu",
}

# Hatırlatma için yeterli olan "durum / gelecek" fiilleri ─────────────────
# Bu fiiller etkinlik kelimeleriyle birlikte geldiğinde hatırlatma sayılır.
_REMINDER_STATE_WORDS: set[str] = {
    "var", "olacak", "yapılacak", "başlayacak", "gerçekleşecek",
    "çıkacak", "istenecek", "gerekecek", "verilecek", "açıklanacak",
    "sorulacak", "anlatılacak", "işlenecek", "gösterilecek",
}

# Zaman ifadeleri (hatırlatmanın geçerli sayılması için en az biri olmalı)
_REMINDER_TIME_WORDS: set[str] = {
    "bugün", "yarın", "öbür", "haftaya", "haftasına",
    "pazartesi", "salı", "çarşamba", "perşembe",
    "cuma", "cumartesi", "pazar",
    "ocak", "şubat", "mart", "nisan", "mayıs", "haziran",
    "temmuz", "ağustos", "eylül", "ekim", "kasım", "aralık",
    "bu hafta", "gelecek hafta", "önümüzdeki", "saat",
}

# ── Aksiyon fiilleri (görev için zorunlu; en az biri bulunmalı) ────────────
# KURAL: Yalnızca güçlü eylem emirleri (fiiller). İsimler (rapor, sunum,
# proje...) ve zayıf zorunluluk ifadeleri (gerek, lazım...) KASITLI olarak
# çıkarıldı — bunlar eğitim içeriklerinde her cümlede geçtiğinden yüzlerce
# yanlış pozitif üretiyordu.
_ACTION_VERBS: list[str] = [
    # Yapma / bitirme
    "yap", "yapın", "yapalım", "yapılacak", "yapılmalı", "yapılması",
    "et", "edin", "edelim",
    "bitir", "bitirin", "bitirelim", "bitirilecek",
    "tamamla", "tamamlayın", "tamamlanacak",
    # Hatırlatma / not alma
    "hatırlat", "hatırlatın", "unutma", "unutmayın", "not al", "not alın",
    # Gönderme / iletme
    "gönder", "gönderin", "gönderelim", "gönderilecek",
    "ilet", "iletin", "iletilecek",
    "yükle", "yükleyin",
    # Hazırlama / yazma
    "hazırla", "hazırlayın", "hazırlanacak",
    "yaz", "yazın", "yazalım",
    "düzenle", "düzenleyin",
    "güncelle", "güncelleyin",
    # İletişim / görüşme
    "ara", "arayın", "arayalım",
    "çağır", "çağırın",
    "görüş", "görüşün", "görüşelim",
    # Teslim / takip — SADECE fiil formları (isim "teslim" çıkarıldı)
    "teslim et", "teslim edilecek",
    "takip et", "kontrol et", "incele", "inceleyin",
    "planla", "organize et",
    # Güçlü kişisel yükümlülük — özne belli ve eylem net
    "yapmalısın", "yapmalısınız", "yapmalıyım", "yapmalıyız",
    "etmelisin", "etmelisiniz",
    "gitmelisin", "gitmeliyiz",
]

# ── Konu anlatımı / açıklama cümleleri – GÖREV ÇIKARTILMAZ ─────────────────
# Bu kalıpları içeren cümleler büyük olasılıkla eğitim/bilgi aktarımıdır,
# kişisel eylem emri değildir.
_EXPLANATION_RE = re.compile(
    r"\b(örneğin|mesela|demek\s+ki|anlamına\s+gelir|ifade\s+eder|"
    r"denilebilir|söylenebilir|kabul\s+edil|bu\s+kural|bu\s+formül|"
    r"bu\s+yöntem|bu\s+kavram|şu\s+anlama|buna\s+göre|dolayısıyla|"
    r"başka\s+bir\s+deyişle|özetle\s+söyle)\b",
    re.IGNORECASE | re.UNICODE,
)

# Bir kayıt başına üretilebilecek maksimum görev sayısı
_MAX_TASKS_PER_RECORDING: int = 10

# Minimum anlamlı kelime sayısı
_MIN_WORD_COUNT = 4

# Maksimum kelime sayısı — bu sınırı aşan "cümle" büyük ihtimalle
# sürekli metin (şarkı sözü, transkript gürültüsü) olduğundan
# gerçek bir görev değildir.
_MAX_WORD_COUNT = 22

# Görev başlığı Flutter'da gösterilirken en fazla bu kadar kelime alır.
_MAX_TITLE_WORDS = 10

# ── Selamlama & sohbet kalıpları – bu cümlelerden görev ÇIKARTILMAZ ────────
_GREETING_RE = re.compile(
    r"^(merhaba|nasılsın|nasılsınız|iyi günler|günaydın|iyi akşamlar|"
    r"iyi geceler|selam|hey|ho|hi|teşekkür|teşekkürler|sağ ol|sağ olun|"
    r"kolay gelsin|ne var ne yok|naber|iyiyim|tamam|peki|harika|süper|"
    r"görüşürüz|hoşça kal|bay bay)\b",
    re.IGNORECASE | re.UNICODE,
)

# ── Cümle başı gürültü bağlaçları ──────────────────────────────────────────
_NOISE_RE = re.compile(
    r"^(ve\s+|bir\s+|ama\s+|fakat\s+|lakin\s+|"
    r"ki\s+|da\s+|de\s+|ile\s+|"
    r"yani\s+|zaten\s+|işte\s+|"
    r"o\s+zaman\s+|belki\s+|herhalde\s+)+",
    re.IGNORECASE | re.UNICODE,
)

# ── Haftanın günleri (Türkçe → weekday index, Pazartesi=0) ────────────────
_WEEKDAY_MAP: dict[str, int] = {
    "pazartesi": 0, "salı": 1, "çarşamba": 2, "perşembe": 3,
    "cuma": 4, "cumartesi": 5, "pazar": 6,
}

# ── Ay adları (Türkçe → ay numarası) ──────────────────────────────────────
_MONTH_MAP: dict[str, int] = {
    "ocak": 1,  "şubat": 2,  "mart": 3,    "nisan": 4,
    "mayıs": 5, "haziran": 6, "temmuz": 7,  "ağustos": 8,
    "eylül": 9, "ekim": 10,  "kasım": 11,  "aralık": 12,
}

# ── Whisper fonetik hata → doğru ay adı haritası ───────────────────────────
# Whisper özellikle yabancı dil/aksanlı Türkçe'de ay adlarını bozar.
_MONTH_VARIANTS: dict[str, list[str]] = {
    "ocak":    ["ocak", "ocag", "okak", "ucak", "ocack", "ojak", "ocac",
                "ocağ", "ocağı", "ocakk", "oçak"],
    "şubat":   ["şubat", "şubad", "subat", "shubat", "subad", "şubatt",
                "subatt", "şubbat", "şubbad"],
    "mart":    ["mart", "mard", "martt", "martt", "mart'ta", "mart'ın"],
    "nisan":   ["nisan", "nizan", "nişan", "nisamn", "nissan", "nizzan",
                "nişen", "nisaan", "nisen", "nizam"],
    "mayıs":   ["mayıs", "mayis", "meis", "maıs", "meyis", "mayış",
                "mayız", "mayyıs", "mayes", "mayiss", "mays", "mais",
                "meiss", "meiş", "mayıss", "maıss", "meıs", "mayss",
                "meyiss", "maiss", "mayıss", "maış", "mayız", "mayyis",
                "mayiss", "maıys", "mehis", "me'is"],
    "haziran": ["haziran", "hazıran", "haziram", "hazıram", "haziron",
                "haziiran", "hazran", "hazirem", "haziran", "haziran",
                "hazerran", "haziranı", "hazirant", "heziram"],
    "temmuz":  ["temmuz", "temmüz", "temuz", "temüz", "temmûz", "temmus",
                "temmuss", "temmüss", "temuuz", "temüüz"],
    "ağustos": ["ağustos", "augustos", "ağusdos", "ağustus", "ağıstos",
                "agustos", "ağustus", "augustus", "auğustos", "aağustos",
                "aağısdos", "ağustoss", "ağüstos"],
    "eylül":   ["eylül", "eylul", "aylül", "eylûl", "aylul", "eylüll",
                "eylull", "aylüll", "eylüil", "eylull", "eylul", "eylüül"],
    "ekim":    ["ekim", "ekım", "ekimm", "ekimm", "ekim", "akim", "ekimm"],
    "kasım":   ["kasım", "kasim", "kasem", "qasım", "kasum", "kasimm",
                "kasın", "qasim", "kassım", "kasimm", "casım", "kasîm",
                "kasimm", "casim"],
    "aralık":  ["aralık", "aralik", "arali", "aralı", "araliq", "arralık",
                "aralikk", "aralıq", "aralük", "arlık", "aralik", "aralig",
                "aralique", "aralik", "arralık"],
}

# Gün isimleri için Whisper hata haritası
_DAY_VARIANTS: dict[str, list[str]] = {
    "pazartesi": ["pazartesi", "pazartezi", "pazartezı", "pazartessi",
                  "pazarrtesi", "pazarrtezi", "paazartesi"],
    "salı":      ["salı", "sali", "saalı", "salıı", "salii", "salı", "saly"],
    "çarşamba":  ["çarşamba", "carsamba", "çarsamba", "çarşampa", "çarşamba",
                  "charsamba", "çarşamba", "charşamba"],
    "perşembe":  ["perşembe", "persembe", "pershembe", "perşombe", "perşempe",
                  "perşemb", "pershemb", "persombe"],
    "cuma":      ["cuma", "juma", "cümma", "cumaa", "jüma"],
    "cumartesi": ["cumartesi", "cumartezi", "cumartesi", "cumartezi",
                  "cümartesi", "cumartesii", "cumartesi"],
    "pazar":     ["pazar", "pazzar", "pazzarr", "pazarr"],
}

_DAY_VARIANT_TO_DAY: dict[str, str] = {
    v: correct
    for correct, variants in _DAY_VARIANTS.items()
    for v in variants
}

# Sık Whisper hataları — doğrudan kelime değişimi (kısa liste, hızlı)
_WORD_FIXES: dict[str, str] = {
    "bugün":    ["bugun", "bugüm", "bugum", "bugûn", "buğun"],
    "yarın":    ["yarın", "yarin", "yarın", "yarınn", "yarnn"],
    "hafta":    ["haftta", "haftaa", "haffta"],
    "toplantı": ["toplantı", "toplanti", "topllantı", "toplantii",
                 "toplantü", "toplantii"],
    "sınav":    ["sınav", "sinav", "sıınav", "sinavv", "sınaav"],
    "ödev":     ["ödev", "odev", "öddев", "ödevv"],
    "proje":    ["projje", "prooje", "proje", "projee"],
    "sunum":    ["sunuum", "sunnım", "sunumm", "sunum"],
    "rapor":    ["rappor", "raapor", "raporr", "rapoor"],
    "görüşme":  ["görüşme", "gorusme", "görüşmee", "görüşmee", "görüşme"],
}

_WORD_FIX_MAP: dict[str, str] = {
    v: correct
    for correct, variants in _WORD_FIXES.items()
    for v in variants
}

# Ters harita: varyant → doğru ay adı
_VARIANT_TO_MONTH: dict[str, str] = {
    v: correct
    for correct, variants in _MONTH_VARIANTS.items()
    for v in variants
}

# difflib için tüm varyantların düz listesi
_ALL_VARIANTS: list[str] = list(_VARIANT_TO_MONTH.keys())

# Ay adına benzeyen kelimelerin minimum/maksimum uzunluğu (performans filtresi)
_MONTH_LEN_RANGE = (3, 9)


def _normalize_months(text: str) -> str:
    """
    Whisper fonetik hatalarını düzeltir:
      - Ay adları (ocak…aralık)
      - Gün adları (pazartesi…pazar)
      - Sık kullanılan Türkçe kelimeler (toplantı, sınav…)

    Strateji:
      1. Statik varyant haritasında tam eşleşme (hızlı yol)
      2. difflib.get_close_matches ile bulanık eşleşme (cutoff=0.78)
    """
    import difflib

    # Tüm statik haritaları birleştir
    combined_map: dict[str, str] = {}
    combined_map.update(_VARIANT_TO_MONTH)
    combined_map.update(_DAY_VARIANT_TO_DAY)
    combined_map.update(_WORD_FIX_MAP)
    all_keys: list[str] = list(combined_map.keys())

    words = text.split()
    result: list[str] = []
    for word in words:
        clean = re.sub(r"[^\w]", "", word.lower())
        lo, hi = _MONTH_LEN_RANGE  # 3–9 karakter; kelime düzeltmeleri için yeterli aralık
        if lo <= len(clean) <= 12:
            # 1. Statik harita
            if clean in combined_map:
                result.append(combined_map[clean])
                continue
            # 2. Fuzzy eşleşme — sadece ay/gün/kısa kelimeler için
            if len(clean) <= 10:
                close = difflib.get_close_matches(
                    clean, all_keys, n=1, cutoff=0.80
                )
                if close:
                    result.append(combined_map[close[0]])
                    continue
        result.append(word)
    return " ".join(result)


# "3 gün sonra", "2 hafta sonra", "1 ay sonra" gibi dinamik ifadeler
_RELATIVE_DATE_RE = re.compile(r"(\d+)\s*(gün|hafta|ay)\s*sonra", re.IGNORECASE | re.UNICODE)

# "saat 14:30", "saat 3" gibi saatler → bugün kabul edilir
_TIME_RE = re.compile(r"saat\s*\d{1,2}([:h]\d{2})?", re.IGNORECASE | re.UNICODE)


def _resolve_date(lower: str, today: date) -> date | None:
    """
    Türkçe zaman ifadesini gerçek bir date nesnesine çevirir.

    Desteklenen ifadeler:
      - Kesin: "bugün", "yarın", "öbür gün", "bu hafta", "haftaya",
               "gelecek hafta", "bu ay", "gelecek ay"
      - Saat (saat 14 vb.) → aynı gün
      - Gün adları: "pazartesi" … "pazar" → sonraki o gün
      - Göreli: "3 gün sonra", "2 hafta sonra", "1 ay sonra"
      - Ay adları: "ocak" … "aralık" → o ayın 15'i (yaklaşık)
    Hiçbiri eşleşmezse None döner.

    Whisper fonetik hataları (_normalize_months) otomatik düzeltilir.
    """
    # Whisper hatalarını düzelt ("meis" → "mayıs" vb.)
    lower = _normalize_months(lower)
    # ── Kesin ifadeler ─────────────────────────────────────────────────────
    if "bugün" in lower or "bu gün" in lower:
        return today
    if _TIME_RE.search(lower):          # "saat X" → bugün
        return today
    if "yarın" in lower:
        return today + timedelta(days=1)
    if "öbür gün" in lower:
        return today + timedelta(days=2)
    if "bu hafta" in lower:
        return today + timedelta(days=4)   # hafta ortası yaklaşık
    if "haftaya" in lower or "gelecek hafta" in lower or "önümüzdeki hafta" in lower:
        return today + timedelta(weeks=1)
    if "bu ay" in lower:
        return today + timedelta(days=14)  # ay ortası yaklaşık
    if "gelecek ay" in lower or "önümüzdeki ay" in lower:
        return today + timedelta(days=30)

    # ── Haftanın günleri → sonraki o gün ──────────────────────────────────
    for name, wd in _WEEKDAY_MAP.items():
        if name in lower:
            days_ahead = (wd - today.weekday() + 7) % 7
            if days_ahead == 0:
                days_ahead = 7  # bugün aynı günse → gelecek haftaya at
            return today + timedelta(days=days_ahead)

    # ── Göreli ifadeler: "3 gün sonra" vb. ────────────────────────────────
    m = _RELATIVE_DATE_RE.search(lower)
    if m:
        n, unit = int(m.group(1)), m.group(2).lower()
        if unit == "gün":
            return today + timedelta(days=n)
        if unit == "hafta":
            return today + timedelta(weeks=n)
        if unit == "ay":
            return today + timedelta(days=n * 30)

    # ── "15 mayıs", "3 haziran" gibi gün+ay ifadeleri ──────────────────────
    gun_ay_pattern = re.compile(
        r'(\d{1,2})\s*(ocak|şubat|mart|nisan|mayıs|haziran|temmuz|'
        r'ağustos|eylül|ekim|kasım|aralık)',
        re.IGNORECASE | re.UNICODE
    )
    m_ga = gun_ay_pattern.search(lower)
    if m_ga:
        gun = int(m_ga.group(1))
        ay_adi = m_ga.group(2).lower()
        ay_num = _MONTH_MAP.get(ay_adi)
        if ay_num:
            year = today.year
            if ay_num < today.month or (ay_num == today.month and gun < today.day):
                year += 1
            try:
                return date(year, ay_num, gun)
            except ValueError:
                pass

    # ── Ay adları → o ayın 15'i (yaklaşık) ────────────────────────────────
    for month_name, month_num in _MONTH_MAP.items():
        if month_name in lower:
            year = today.year
            if month_num < today.month:
                year += 1   # geçmiş ay adı → gelecek yıla at
            try:
                return date(year, month_num, 15)
            except ValueError:
                return date(year, month_num, 1)

    return None


def _clean_sentence(sentence: str) -> str:
    """Cümle başındaki gürültü bağlaçlarını temizler."""
    return _NOISE_RE.sub("", sentence).strip()


def _tokenize(lower: str) -> set[str]:
    """Türkçe unicode'a uyumlu kelime tokenizer."""
    return set(re.split(r"[^\wçğışöüÇĞİŞÖÜ]+", lower, flags=re.UNICODE))


def _has_action_verb(lower: str) -> bool:
    """
    Cümlede aksiyon fiili var mı? Substring değil, TAM KELİME eşleşmesi arar.
    İki kelimeli fiiller ("teslim et") için alt-dizi kontrolü yeterli.
    """
    tokens = _tokenize(lower)
    for kw in _ACTION_VERBS:
        if " " in kw:
            if kw in lower:
                return True
        else:
            if kw in tokens:
                return True
    return False


def _is_reminder(lower: str) -> bool:
    """
    Cümle aksiyon fiili içermese de önemli bir hatırlatma mı?

    Koşul: Aşağıdakilerin ÜÇÜ birden sağlanmalı:
      1) Bir etkinlik kelimesi var  (sınav, ders, ödev, vize …)
      2) Bir durum/gelecek fiili var (var, olacak, çıkacak …)
      3) Bir zaman ifadesi var       (haftaya, yarın, pazartesi …)

    Böylece "haftaya sınav var", "yarın ders var",
    "veri yapıları çıkacak sınavda" gibi cümleler yakalanır.
    """
    tokens = _tokenize(lower)

    has_event = bool(tokens & _REMINDER_EVENT_WORDS)
    has_state = bool(tokens & _REMINDER_STATE_WORDS)

    # Zaman kelimeleri: token listesinde tam eşleşme VEYA alt-dizi
    has_time = bool(tokens & _REMINDER_TIME_WORDS) or any(
        tw in lower for tw in _REMINDER_TIME_WORDS if " " in tw
    )

    return has_event and has_state and has_time


def _score_sentence(sentence: str, lower: str, today) -> float:
    """
    Bir cümlenin 'aksiyon/görev' olma olasılığını 0.0–1.0 arasında puanlar.

    Puanlama kriterleri:
      +0.35  → Aksiyon fiili var (_has_action_verb)
      +0.25  → Zaman/tarih ifadesi var (_resolve_date != None)
      +0.20  → Hatırlatma deseni var (_is_reminder)
      +0.10  → Kişi zamiri var (ben, biz, sen → kişisel görev)
      +0.10  → Soru değil (? ile bitmiyor)
      -0.30  → Açıklama/konu anlatımı kalıbı (_EXPLANATION_RE eşleşiyor)
      -0.20  → Selamlama kalıbı (_GREETING_RE eşleşiyor)
      -0.15  → Çok kısa (< 4 kelime) veya çok uzun (> 20 kelime)
      -0.10  → Pasif/genel cümle ("denir", "sayılır", "bilinir" gibi)
    """
    score = 0.0
    tokens = _tokenize(lower)
    word_count = len(lower.split())

    if _has_action_verb(lower):
        score += 0.35
    if _resolve_date(lower, today) is not None:
        score += 0.25
    if _is_reminder(lower):
        score += 0.20
    if tokens & {"ben", "biz", "benim", "bizim", "sen", "siz"}:
        score += 0.10
    if not lower.strip().endswith("?"):
        score += 0.10

    if _EXPLANATION_RE.search(lower):
        score -= 0.30
    if _GREETING_RE.search(lower):
        score -= 0.20
    if word_count < 4 or word_count > 20:
        score -= 0.15
    if re.search(
        r'\b(denir|sayılır|bilinir|görülür|kabul edilir|ifade edilir)\b',
        lower, re.IGNORECASE | re.UNICODE
    ):
        score -= 0.10

    return max(0.0, min(1.0, score))


def _generate_record_title(text: str, category: str) -> str:
    """
    Transkript metninden akıllı başlık üretir.
    Öncelik sırası:
      1. Açık ders/konu adı: "X dersi", "X sınavı", "X toplantısı"
      2. Tekrar eden önemli isim (3+ kez geçen, 5+ harf)
      3. İlk anlamlı cümlenin ilk 5 kelimesi
      4. Kategori + tarih
    """
    if not text or not text.strip():
        return f"{category} — {date.today().strftime('%d.%m.%Y')}"

    lower = text.lower()

    # 1. Açık konu+tür kalıbı
    konu_pattern = re.compile(
        r'([\wçğışöüÇĞİŞÖÜ]{3,}(?:\s+[\wçğışöüÇĞİŞÖÜ]{3,})?)\s+'
        r'(dersi?|toplantısı?|sunumu?|sınavı?|ödevi?|projesi?'
        r'|vizesi?|kursu?|eğitimi?|semineri?)',
        re.IGNORECASE | re.UNICODE
    )
    m = konu_pattern.search(lower)
    if m:
        raw = text[m.start():m.end()].strip()
        return raw[0].upper() + raw[1:50]

    # 2. En sık geçen anlamlı kelime (isim adayı, 3+ kez, 5+ harf)
    _STOP = {
        "bir","bu","şu","o","ve","ile","de","da","ki","mi","mu","mü","mı",
        "için","ama","fakat","çünkü","ya","veya","gibi","kadar","daha",
        "çok","az","en","ne","nasıl","neden","hangi","olan","olarak",
        "ise","bile","sadece","hem","var","yok","ben","sen","biz","siz",
        "onlar","bunu","buna","bunun","şunu","yani","işte","zaten",
        "tamam","peki","evet","hayır","tabi","tabii","şimdi","sonra",
        "önce","hadi","neyse","aslında","gerçekten","artık"
    }
    words = re.findall(r'[a-zçğışöüA-ZÇĞİŞÖÜ]{5,}', lower)
    freq: dict[str, int] = {}
    for w in words:
        if w not in _STOP:
            freq[w] = freq.get(w, 0) + 1
    top = [w for w, c in sorted(freq.items(), key=lambda x: x[1], reverse=True)
           if c >= 3]
    if top:
        keyword = top[0][0].upper() + top[0][1:]
        return f"{keyword} — {category}"

    # 3. İlk anlamlı cümlenin ilk 5 kelimesi
    sentences = [s.strip() for s in re.split(r'[.!?\n]', text)
                 if len(s.strip()) > 15]
    if sentences:
        words5 = sentences[0].split()[:5]
        title = " ".join(words5).strip()
        return title[0].upper() + title[1:] if title else f"{category} Kaydı"

    # 4. Fallback
    return f"{category} — {date.today().strftime('%d.%m.%Y')}"


def extract_tasks_from_text(text: str) -> list[dict]:
    today = date.today()
    text = re.sub(r'\s+', ' ', text).strip()
    raw_sentences = re.split(r'[.!?;\n]+', text)
    tasks = []
    seen_tokens: list[set] = []

    # Türkçe'de geçerli olmayan bozuk kelime tespiti
    def _is_garbled(word: str) -> bool:
        # Sesli harf yok ve 4+ karakter = bozuk
        if len(word) >= 4 and not re.search(r'[aeıioöuüAEIİOÖUÜ]', word):
            return True
        # 4+ ünsüz yan yana = bozuk
        if re.search(r'[bcçdfgğhjklmnprsştvyzBCÇDFGĞHJKLMNPRSŞTVYZ]{4,}', word):
            return True
        return False

    def _has_garbled_words(sentence: str) -> bool:
        words = sentence.split()
        garbled = sum(1 for w in words if len(w) > 3 and _is_garbled(w))
        return garbled >= 2 or (len(words) > 0 and garbled / len(words) > 0.25)

    def _is_question(lower: str) -> bool:
        if lower.strip().endswith('?'):
            return True
        question_words = r'\b(nedir|nasıl|neden|ne\s+kadar|kaç|kim|nerede|ne\s+zaman|hangi|mıdır|midir|mudur|müdür)\b'
        return bool(re.search(question_words, lower, re.IGNORECASE | re.UNICODE))

    def _is_definition(lower: str) -> bool:
        patterns = [
            r'\b(nedir|denir|sayılır|bilinir|tanımlanır|ifade\s+eder|anlamına\s+gelir|olarak\s+adlandırılır)\b',
            r'\b(örneğin|mesela|demek\s+ki|yani|şöyle\s+ki|buna\s+göre)\b',
            r'\b(tanım|kavram|formül|teorem|kural|prensip|ilke)\b',
        ]
        return any(re.search(p, lower, re.IGNORECASE | re.UNICODE) for p in patterns)

    # Güçlü aksiyon fiilleri
    STRONG_VERBS = [
        "teslim et", "teslim edin", "gönderin", "gönder", "yükleyin", "yükle",
        "hazırlayın", "hazırla", "bitirin", "bitir", "tamamlayın", "tamamla",
        "yazın", "yaz", "okuyun", "oku", "arayın", "ara", "görüşün", "görüş",
        "katılın", "katıl", "başvurun", "başvur", "ödeyin", "öde",
        "düzeltin", "düzelt", "güncelleyin", "güncelle", "kontrol et",
        "inceleyin", "incele", "not alın", "not al", "unutmayın", "unutma",
        "hatırlayın", "hatırla", "çalışın", "çalış", "tekrar edin", "tekrar et",
        "ezberleyin", "ezberle", "çözün", "çöz", "yapın", "yap",
        "getirin", "getir", "götürün", "götür", "alın", "ekleyin", "silin",
    ]

    for raw in raw_sentences:
        if len(tasks) >= 8:
            break

        s = raw.strip()
        if not s or len(s) < 12:
            continue

        lower = s.lower()
        words = lower.split()
        word_count = len(words)

        # Uzunluk filtresi
        if word_count < 4 or word_count > 22:
            continue

        # Selamlama filtresi
        if _GREETING_RE.search(lower):
            continue

        # Genişletilmiş selamlama filtresi — cümlenin herhangi bir yerinde
        _EXTENDED_GREETING_RE = re.compile(
            r'\b(hoş\s*geldiniz|hoş\s*geldin|merhaba|günaydın|iyi\s*günler|'
            r'iyi\s*akşamlar|selam|bekleriz|aramıza|katıldığınız|geldiğiniz|'
            r'buyurun|bekleyin|derse\s*hoş|dersinize\s*hoş|sınıfa\s*hoş)\b',
            re.IGNORECASE | re.UNICODE
        )
        if _EXTENDED_GREETING_RE.search(lower):
            continue

        # Soru cümlesi filtresi
        if _is_question(lower):
            continue

        # Tanım/açıklama filtresi
        if _is_definition(lower):
            continue

        # Bozuk kelime filtresi (Whisper halüsinasyonu)
        if _has_garbled_words(s):
            print(f"[NLP] Bozuk kelime içeriyor, atlandı: {s[:50]}")
            continue

        # Tekrarlayan kelime filtresi (Whisper artefaktı)
        unique_ratio = len(set(words)) / len(words) if words else 1
        if unique_ratio < 0.55:
            print(f"[NLP] Tekrarlayan kelimeler, atlandı: {s[:50]}")
            continue

        # PUANLAMA
        score = 0

        # Güçlü aksiyon fiili
        has_strong = any(verb in lower for verb in STRONG_VERBS)
        if has_strong:
            score += 50

        # Zayıf aksiyon fiili
        elif _has_action_verb(lower):
            score += 25

        # Zaman/tarih
        resolved = _resolve_date(lower, today)
        if resolved:
            score += 30

        # Hatırlatma deseni
        is_reminder = _is_reminder(lower)
        if is_reminder:
            score += 35

        # Kişisel zamir
        tokens = _tokenize(lower)
        if tokens & {"ben", "biz", "benim", "bizim", "bende", "bize", "bizde"}:
            score += 10

        # Gelecek zaman
        if re.search(r'(acak|ecek|malı|meli|acağım|eceğim|alacağım)\b', lower, re.UNICODE):
            score += 15

        # Negatif: genel bilgi cümlesi
        if re.search(r'\b(önemli|gerekli|gerekiyor|lazım|şart)\b', lower, re.UNICODE):
            if not has_strong and not is_reminder:
                score -= 15

        # Eşik kontrolü
        # Güçlü fiil varsa 40, hatırlatma varsa 35, diğer 50
        if has_strong:
            threshold = 40
        elif is_reminder:
            threshold = 35
        else:
            threshold = 50

        if score < threshold:
            continue

        # Semantik dedup (Jaccard)
        cleaned = _clean_sentence(s)
        new_tok = _tokenize(cleaned.lower())
        duplicate = False
        for prev in seen_tokens:
            if prev and new_tok:
                j = len(new_tok & prev) / len(new_tok | prev)
                if j > 0.55:
                    duplicate = True
                    break
        if duplicate:
            continue

        seen_tokens.append(new_tok)

        # Başlık
        w = cleaned.split()
        title = (" ".join(w[:_MAX_TITLE_WORDS]) + "…" if len(w) > _MAX_TITLE_WORDS else cleaned)
        title = title[0].upper() + title[1:] if title else title

        tasks.append({
            "task_title": title,
            "due_date": resolved.isoformat() if resolved else None,
            "resolved_date": resolved,
        })
        print(f"[NLP] Aksiyon çıkarıldı (score={score}): {title[:50]}")

    return tasks

@app.on_event("startup")
def on_startup():
    # Yalnızca eksik tabloları oluşturur; mevcut verilere dokunmaz.
    models.Base.metadata.create_all(bind=engine)
    
@app.get("/")
def root():
    return {"mesaj": "Voice To Action Backend Sunucusu Başarıyla Çalışıyor! 🚀"}


@app.post("/api/register", response_model=schemas.UserOut, status_code=status.HTTP_201_CREATED)
def register(user: schemas.UserRegister, db: Session = Depends(get_db)):
    existing_user = db.query(models.User).filter(models.User.email == user.email).first()
    if existing_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Bu email ile kayıtlı bir kullanıcı zaten var.",
        )

    db_user = models.User(
        full_name=user.full_name,
        email=user.email,
        password=get_password_hash(user.password),  # bcrypt ile hashle
    )
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    return db_user


@app.post("/api/login", response_model=schemas.Token)
def login(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    # 1) Kullanıcıyı e-posta ile bul
    user = db.query(models.User).filter(models.User.email == form_data.username).first()

    # 2) Şifreyi bcrypt ile doğrula
    if not user or not verify_password(form_data.password, user.password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Hatalı şifre veya email",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # 3) JWT access token üret (sub = e-posta)
    access_token = create_access_token(data={"sub": user.email})

    return {
        "access_token": access_token,
        "token_type": "bearer",
        "full_name": user.full_name,
        "user_id": user.id,
    }


@app.post("/upload-audio/")
async def upload_audio(file: UploadFile = File(...)):
    upload_dir = os.path.join(BASE_DIR, "uploads")
    os.makedirs(upload_dir, exist_ok=True)

    unique_filename = f"{uuid.uuid4().hex}_{os.path.basename(file.filename)}"
    file_path = os.path.join(upload_dir, unique_filename)

    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    await file.close()

    return {
        "message": "Ses dosyasi basariyla yuklendi.",
        "file_path": file_path,
    }


@app.post("/api/transcribe")
def transcribe(
    file: UploadFile = File(...),
    category: str = Form("genel"),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    temp_file_path = "temp_audio_video_file"
    db_record = None
    try:
        # ── AŞAMA 1: Geçici dosyaya yaz ─────────────────────────────────────
        try:
            with open(temp_file_path, "wb") as buffer:
                shutil.copyfileobj(file.file, buffer)
            print(f"[transcribe] Dosya yazıldı: {temp_file_path} ({os.path.getsize(temp_file_path)} byte)")
        except Exception as e:
            print(f"[transcribe] HATA — Dosya yazma aşamasında: {e}")
            raise HTTPException(status_code=500, detail=f"Dosya kaydedilemedi: {e}")

        # Sessiz / boş dosya kontrolü (< 4 KB genellikle anlamlı ses içermez)
        file_size = os.path.getsize(temp_file_path)
        if file_size < 4096:
            print(f"[transcribe] SESSİZ KAYIT — Dosya boyutu çok küçük: {file_size} byte")
            return {"text": "", "record_id": None, "tasks": [], "error": "Ses dosyası çok kısa veya sessiz. Lütfen tekrar kaydedin."}

        # ── AŞAMA 2: faster-whisper transkripsiyon (chunked) ────────────────
        transcribed_text: str = ""
        try:
            transcribed_text = _transcribe_audio(temp_file_path)
            print(f"[transcribe] Transkripsiyon tamamlandı. Metin: {len(transcribed_text)} karakter")
        except MemoryError as e:
            print(f"[transcribe] HATA — Bellek yetersiz (MemoryError): {e}")
            return {"text": "", "record_id": None, "tasks": [], "error": "Bellek yetersiz. Daha kısa bir kayıt deneyin."}
        except RuntimeError as e:
            err_msg = str(e)
            print(f"[transcribe] HATA — RuntimeError: {err_msg}")
            # Model yükleme hatasıysa açık mesaj ilet; değilse genel mesaj yeterli.
            user_msg = err_msg if "model yüklenemedi" in err_msg.lower() else "Ses işleme başarısız. Tekrar deneyin."
            return {"text": "", "record_id": None, "tasks": [], "error": user_msg}
        except Exception as e:
            print(f"[transcribe] HATA — Ses tanıma aşamasında beklenmedik hata: {e}")
            return {"text": "", "record_id": None, "tasks": [], "error": "Ses tanıma başarısız. Tekrar deneyin."}

        # Whisper çıktısı boşsa sessiz kayıt say
        if not transcribed_text:
            print("[transcribe] SESSİZ KAYIT — Whisper boş metin döndürdü.")
            return {"text": "", "record_id": None, "tasks": [], "error": "Ses kaydında konuşma tespit edilemedi."}

        # ── AŞAMA 3: Veritabanına kaydet ────────────────────────────────────
        try:
            db_record = models.Record(
                user_id=current_user.id,
                filename=file.filename or "bilinmiyor",
                category=category,
                status="tamamlandi",
                transcribed_text=transcribed_text,
            )
            db.add(db_record)
            db.commit()
            db.refresh(db_record)
            print(f"[transcribe] Kayıt DB'ye eklendi. record_id={db_record.id}")
        except Exception as e:
            print(f"[transcribe] HATA — Veritabanı kayıt aşamasında: {e}")
            db.rollback()
            raise HTTPException(status_code=500, detail=f"Kayıt veritabanına eklenemedi: {e}")

        # ── AŞAMA 4: NLP ile görev çıkar ve kaydet ──────────────────────────
        try:
            # Whisper fonetik hatalarını NLP'den önce düzelt
            normalized_text = _normalize_months(transcribed_text)
            if normalized_text != transcribed_text:
                print(f"[transcribe] Ay adı normalizasyonu uygulandı.")
            extracted_tasks = extract_tasks_from_text(normalized_text)
            print(f"[transcribe] NLP tamamlandı. Çıkarılan görev sayısı: {len(extracted_tasks)}")
            for task_data in extracted_tasks:
                resolved: date | None = task_data.get("resolved_date")
                db_deadline = (
                    datetime(resolved.year, resolved.month, resolved.day, 23, 59)
                    if resolved else None
                )
                db_task = models.Task(
                    record_id=db_record.id,
                    title=task_data["task_title"][:255],
                    deadline=db_deadline,
                    is_completed=False,
                )
                db.add(db_task)
            db.commit()
        except Exception as e:
            print(f"[transcribe] HATA — Görev kayıt aşamasında: {e}")
            db.rollback()
            raise HTTPException(status_code=500, detail=f"Görevler kaydedilemedi: {e}")

        flutter_tasks = [
            {"task_title": t["task_title"], "due_date": t["due_date"]}
            for t in extracted_tasks
        ]
        return {
            "text": transcribed_text,
            "record_id": db_record.id,
            "tasks": flutter_tasks,
            "auto_title": _generate_record_title(transcribed_text, category),
            "original_filename": file.filename,
        }

    finally:
        file.file.close()
        if os.path.exists(temp_file_path):
            if db_record is not None:
                try:
                    upload_dir = os.path.join(BASE_DIR, "uploads")
                    os.makedirs(upload_dir, exist_ok=True)
                    # Orijinal uzantıyı koru (.m4a, .webm, .mp3 vb.)
                    _, orig_ext = os.path.splitext(file.filename or "")
                    if not orig_ext:
                        orig_ext = ".audio"
                    permanent_path = os.path.join(upload_dir, f"rec_{db_record.id}{orig_ext}")
                    shutil.copy(temp_file_path, permanent_path)
                    print(f"[transcribe] Ses dosyası kalıcı kaydedildi: {permanent_path}")
                except Exception as e:
                    print(f"[transcribe] UYARI — Kalıcı kopya oluşturulamadı: {e}")
            os.remove(temp_file_path)


@app.get("/api/records/{record_id}/audio")
def stream_audio(
    record_id: int,
    token: str = Query(..., description="JWT access token"),
    db: Session = Depends(get_db),
):
    """
    Ses dosyasını stream eder.
    audioplayers header desteklemediğinden token query param olarak alınır.
    """
    from auth import ALGORITHM, SECRET_KEY
    from jose import JWTError
    from jose import jwt as _jwt

    try:
        payload = _jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        email: str | None = payload.get("sub")
        if not email:
            raise HTTPException(status_code=401, detail="Geçersiz token.")
    except JWTError:
        raise HTTPException(status_code=401, detail="Geçersiz veya süresi dolmuş token.")

    user = db.query(models.User).filter(models.User.email == email).first()
    if not user:
        raise HTTPException(status_code=401, detail="Kullanıcı bulunamadı.")

    record = db.query(models.Record).filter(
        models.Record.id == record_id,
        models.Record.user_id == user.id
    ).first()
    if not record:
        raise HTTPException(status_code=404, detail="Kayıt bulunamadı.")

    # Orijinal uzantıya sahip dosyayı bul (rec_22.m4a, rec_22.webm, rec_22.audio …)
    import glob as _glob
    import mimetypes as _mt
    pattern = os.path.join(BASE_DIR, "uploads", f"rec_{record_id}.*")
    matches = _glob.glob(pattern)
    if not matches:
        raise HTTPException(status_code=404, detail="Ses dosyası bulunamadı.")

    # Birden fazla eşleşme varsa en büyük dosyayı seç
    audio_path = max(matches, key=os.path.getsize)

    size = os.path.getsize(audio_path)
    if size > 30 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="Dosya 30MB sınırını aşıyor.")

    # Uzantıdan MIME type tespit et
    # .audio veya bilinmeyen uzantı → magic bytes ile tespit dene
    mime_type, _ = _mt.guess_type(audio_path)
    if not mime_type or mime_type == "application/octet-stream":
        with open(audio_path, "rb") as _f:
            header = _f.read(12)
        if header[4:8] in (b"ftyp", b"free", b"mdat"):
            mime_type = "audio/mp4"   # .m4a / .mp4 container
        elif header[:4] == b"fLaC":
            mime_type = "audio/flac"
        elif header[:4] == b"RIFF":
            mime_type = "audio/wav"
        elif header[:3] == b"ID3" or (len(header) >= 2 and header[:2] == b"\xff\xfb"):
            mime_type = "audio/mpeg"
        elif header[:4] == b"OggS":
            mime_type = "audio/ogg"
        elif header[:4] == b"\x1aE\xdf\xa3":
            mime_type = "audio/webm"
        else:
            mime_type = "audio/mp4"   # Android için en güvenli varsayılan

    return FileResponse(audio_path, media_type=mime_type)


@app.get("/api/records")
def get_user_records(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """
    JWT token sahibinin kayıtlarını döner.
    URL'de user_id parametresi YOK — kimlik doğrulama tamamen JWT üzerinden.
    Bu sayede SharedPreferences'taki user_id uyumsuzluğu 403'e yol açamaz.
    """
    records = (
        db.query(models.Record)
        .filter(models.Record.user_id == current_user.id)
        .order_by(models.Record.id.desc())
        .all()
    )
    return [
        {
            "id": r.id,
            "file_name": r.filename,
            "auto_title": r.filename.rsplit(".", 1)[0] if r.filename else f"Kayıt {r.id}",
            "category": r.category or "Diğer",
            "transcript": r.transcribed_text,
            "notes": r.notes,
            "assistant_notes": r.assistant_notes,
            "status": r.status,
            "created_at": r.created_at.isoformat() if r.created_at else None,
        }
        for r in records
    ]


@app.patch("/api/records/{record_id}", status_code=status.HTTP_200_OK)
def update_record(
    record_id: int,
    notes: str | None = Form(default=None),
    assistant_notes: str | None = Form(default=None),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Kaydın kullanıcı notunu ve/veya asistan notunu günceller."""
    record = (
        db.query(models.Record)
        .filter(models.Record.id == record_id,
                models.Record.user_id == current_user.id)
        .first()
    )
    if not record:
        raise HTTPException(status_code=404, detail="Kayıt bulunamadı.")
    if notes is not None:
        record.notes = notes
    if assistant_notes is not None:
        record.assistant_notes = assistant_notes
    db.commit()
    return {"id": record_id, "notes": record.notes, "assistant_notes": record.assistant_notes}


@app.delete("/api/records/{record_id}", status_code=status.HTTP_200_OK)
def delete_record(
    record_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """
    Bir ses kaydını (ve ona bağlı tüm görevleri) kalıcı olarak siler.
    Yalnızca kaydın sahibi olan kullanıcı bu işlemi yapabilir.
    """
    record = (
        db.query(models.Record)
        .filter(models.Record.id == record_id)
        .first()
    )

    if not record:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Kayıt bulunamadı.",
        )

    if record.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Bu kaydı silme yetkiniz yok.",
        )

    # Bağlı görevleri bulk-delete et.
    # synchronize_session=False → SQLAlchemy identity map'i taramaz; daha hızlı
    # ve identity map ile çakışma yaratmaz.
    db.query(models.Task).filter(
        models.Task.record_id == record_id
    ).delete(synchronize_session=False)

    db.delete(record)

    # flush() → DELETE SQL'ini bağlantıya gönder (transaction henüz açık).
    # commit() → transaction'ı kalıcı hale getirir.
    # expire_all() → SQLAlchemy in-memory cache'ini temizler; sonraki
    # sorgu doğrudan veritabanına gider, eski nesneyi döndürmez.
    db.flush()
    db.commit()
    db.expire_all()

    # Doğrulama: commit sonrası kayıt gerçekten yok mu?
    still_exists = db.query(models.Record).filter(
        models.Record.id == record_id
    ).first()
    if still_exists:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Kayıt veritabanından silinemedi. Lütfen tekrar deneyin.",
        )

    return {"message": "Kayıt başarıyla silindi"}


@app.get("/api/tasks/urgent")
def get_urgent_tasks(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """
    Kullanıcının ACİL görevlerini döner.

    Acil sayılma koşulları (her ikisi de sağlanmalı):
      1) is_completed == False  (henüz tamamlanmamış)
      2) deadline'ı var VE şu andan itibaren 48 saat içinde

    Sonuçlar deadline'a göre artan sırayla döner.
    """
    cutoff = datetime.utcnow() + timedelta(hours=48)

    record_ids = [
        r.id
        for r in db.query(models.Record.id)
        .filter(models.Record.user_id == current_user.id)
        .all()
    ]
    if not record_ids:
        return []

    tasks = (
        db.query(models.Task)
        .filter(
            models.Task.record_id.in_(record_ids),
            models.Task.is_completed == False,   # noqa: E712
            models.Task.deadline.isnot(None),
            models.Task.deadline <= cutoff,
        )
        .order_by(models.Task.deadline.asc())
        .all()
    )

    return [
        {
            "id": t.id,
            "record_id": t.record_id,
            "title": t.title,
            "due_date": t.deadline.date().isoformat() if t.deadline else None,
            "status": "done" if t.is_completed else "pending",
            "is_completed": t.is_completed,
        }
        for t in tasks
    ]


@app.get("/api/tasks")
def get_user_tasks(
    pending_only: bool = Query(False, description="True ise sadece tamamlanmamış görevleri döner, due_date'e göre sıralar."),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """
    JWT token sahibinin görevlerini listeler.
    URL'de user_id parametresi YOK — kimlik doğrulama tamamen JWT üzerinden.

    Parametreler:
      - pending_only=false (varsayılan): tüm görevler, en yeni önce.
      - pending_only=true: sadece tamamlanmamış görevler, due_date'e göre
        artan sıra (due_date'i olmayanlar en sona).
    """
    record_ids = [
        r.id
        for r in db.query(models.Record.id)
        .filter(models.Record.user_id == current_user.id)
        .all()
    ]
    if not record_ids:
        return []

    query = db.query(models.Task).filter(models.Task.record_id.in_(record_ids))

    if pending_only:
        # Sadece tamamlanmamış görevler; deadline'ı olanlar önce (artan), null'lar sona
        query = query.filter(models.Task.is_completed == False)  # noqa: E712
        tasks = query.order_by(models.Task.deadline.asc()).all()
        # SQLAlchemy NULL'ları asc()'de öne koyar; Python seviyesinde düzeltelim
        tasks = sorted(tasks, key=lambda t: (t.deadline is None, t.deadline))
    else:
        tasks = query.order_by(models.Task.id.desc()).all()

    return [
        {
            "id": t.id,
            "record_id": t.record_id,
            "title": t.title,
            "due_date": str(t.deadline) if t.deadline else None,
            "status": "done" if t.is_completed else "pending",
            "is_completed": t.is_completed,
        }
        for t in tasks
    ]


@app.delete("/api/tasks/{task_id}", status_code=status.HTTP_200_OK)
def delete_task(
    task_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """
    Bir görevi kalıcı olarak siler.
    Yalnızca görevin sahibi olan kullanıcı bu işlemi yapabilir.
    """
    task = db.query(models.Task).filter(models.Task.id == task_id).first()
    if not task:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Görev bulunamadı.",
        )

    # Ownership: görevin bağlı kaydı bu kullanıcıya ait mi?
    record = (
        db.query(models.Record)
        .filter(
            models.Record.id == task.record_id,
            models.Record.user_id == current_user.id,
        )
        .first()
    )
    if not record:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Bu göreve erişim yetkiniz yok.",
        )

    db.delete(task)
    db.flush()
    db.commit()
    db.expire_all()

    # Doğrulama: commit sonrası görev gerçekten yok mu?
    still_exists = db.query(models.Task).filter(
        models.Task.id == task_id
    ).first()
    if still_exists:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Görev veritabanından silinemedi. Lütfen tekrar deneyin.",
        )

    return {"message": "Görev başarıyla silindi.", "deleted_id": task_id}


@app.put("/api/tasks/{task_id}/toggle")
def toggle_task(
    task_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """
    Görevin is_completed değerini tersine çevirir (True ↔ False).
    Yalnızca görevin sahibi olan kullanıcı bu işlemi yapabilir.
    """
    task = db.query(models.Task).filter(models.Task.id == task_id).first()
    if not task:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Görev bulunamadı.")

    # Ownership kontrolü: görevin bağlı olduğu kayıt bu kullanıcıya ait mi?
    record = (
        db.query(models.Record)
        .filter(
            models.Record.id == task.record_id,
            models.Record.user_id == current_user.id,
        )
        .first()
    )
    if not record:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Bu göreve erişim yetkiniz yok.",
        )

    task.is_completed = not task.is_completed
    db.commit()
    db.refresh(task)

    return {
        "id": task.id,
        "title": task.title,
        "is_completed": task.is_completed,
        "status": "done" if task.is_completed else "pending",
        "message": "✅ Tamamlandı" if task.is_completed else "↩️ Geri alındı",
    }


@app.put("/api/update-profile")
def update_profile(
    newName: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),  # JWT koruması
):
    """Token sahibinin adını günceller."""
    current_user.full_name = newName
    db.commit()
    db.refresh(current_user)
    return {"message": "Profil güncellendi"}


# ─────────────────────────────────────────────────────────────────────────────
# CHATBOT  —  POST /api/chat   (Deterministik State Machine, v5 – CMD tabanlı)
#
# Yanıt formatı: {"answer": str, "options": list[str]}
#
# Flutter butonlardan CMD kodu gönderir (örn: CMD_SELECT_4).
# Bu sayede kelime eşleştirmesi tamamen devre dışı → sonsuz döngü imkansız.
# Ollama SADECE SUMMARIZE / ANALYZE / EMAIL / SENTIMENT durumlarında çalışır.
# ─────────────────────────────────────────────────────────────────────────────

_MAIN_OPTIONS = ["CMD_TASKS", "CMD_RECORDS", "CMD_TOPICS_0"]

_GREETING_WORDS = {
    "sa", "selam", "merhaba", "hey", "hi", "hello",
    "günaydın", "iyi günler", "naber", "nasılsın",
    "yardım", "menü", "ne yapabilirsin", "yardımcı ol", "ana",
}


# ── Sık kullanılan helper'lar ─────────────────────────────────────────────────

def _get_record(record_id: int, user_id: int, db) -> "models.Record | None":
    return (
        db.query(models.Record)
        .filter(models.Record.id == record_id, models.Record.user_id == user_id)
        .first()
    )


def _action_options(record_id: int) -> list:
    return [
        f"CMD_SUMMARIZE_{record_id}",
        f"CMD_ANALYZE_{record_id}",
        f"CMD_CALENDAR_{record_id}",
        f"CMD_MEETING_{record_id}",
        f"CMD_EXAM_{record_id}",
        "CMD_MENU",
    ]


def _no_record_resp(record_id: int) -> dict:
    return {
        "answer": "Seçilen kayıt bulunamadı veya size ait değil.",
        "options": ["CMD_RECORDS", "CMD_MENU"],
    }


def _empty_transcript_resp(record_id: int) -> dict:
    return {
        "answer": "Bu kaydın transkript metni henüz işlenmedi.",
        "options": ["CMD_RECORDS", "CMD_MENU"],
    }


# ── Yanıt template helper'ları ────────────────────────────────────────────────

def _fmt_task_count(tasks) -> str:
    pending = [t for t in tasks if not t.is_completed]
    done    = [t for t in tasks if t.is_completed]
    urgent  = [t for t in pending if t.deadline and
               t.deadline <= datetime.utcnow() + timedelta(hours=48)]
    if not pending:
        return "✅ Tüm görevler tamamlandı, harikasın!"
    parts = [f"📋 {len(pending)} bekleyen görev"]
    if urgent:
        parts.append(f"🔥 {len(urgent)} tanesi ACİL (48 saat içinde)")
    if done:
        parts.append(f"✅ {len(done)} tamamlanan")
    return " · ".join(parts)


def _fmt_record_count(records) -> str:
    if not records:
        return "Henüz ses kaydın yok."
    cats = {}
    for r in records:
        cats[r.category or "Diğer"] = cats.get(r.category or "Diğer", 0) + 1
    cat_str = ", ".join(f"{v} {k}" for k, v in cats.items())
    return f"🎙️ Toplam {len(records)} kayıt: {cat_str}"


def _greeting_msg(user, db) -> str:
    today = date.today()
    tasks = db.query(models.Task).join(
        models.Record, models.Task.record_id == models.Record.id
    ).filter(models.Record.user_id == user.id,
             models.Task.is_completed == False).all()  # noqa: E712
    records = db.query(models.Record).filter(
        models.Record.user_id == user.id).all()
    urgent = [t for t in tasks if t.deadline and
              t.deadline <= datetime.utcnow() + timedelta(hours=48)]

    # Bu hafta sınav/ödev var mı?
    week_end = today + timedelta(days=7)
    week_exam_tasks = [
        t for t in tasks
        if t.deadline
        and today <= t.deadline.date() <= week_end
        and any(w in t.title.lower()
                for w in ["sınav", "ödev", "vize", "final", "sunum", "teslim"])
    ]

    # Toplam transkript kelime sayısı
    total_words = sum(len((r.transcribed_text or "").split()) for r in records)

    name = user.full_name.split()[0] if user.full_name else "Merhaba"

    # Güne özel selamlama (0=Pazartesi, 6=Pazar)
    day_greetings = {
        0: "Haftaya güçlü başlıyoruz 💪",
        1: "Salı enerjisiyle devam 🚀",
        2: "Haftanın ortasındayız, devam 🔥",
        3: "Perşembeyi de atlattık, az kaldı ⚡",
        4: "Haftayı güzel kapatalım 🎯",
        5: "Cumartesi molası, ama planlı 📋",
        6: "Pazar günü, yarına hazırlık zamanı ☀️",
    }
    day_msg = day_greetings.get(today.weekday(), "Günaydın!")

    lines = [f"👋 Merhaba {name}! {day_msg}", ""]

    if urgent:
        lines.append(f"🔥 **DİKKAT:** {len(urgent)} acil görevin var (48 saat içinde)!")
    for t in week_exam_tasks[:2]:
        due_str = t.deadline.strftime("%d %B") if t.deadline else ""
        lines.append(
            f"📚 Bu hafta: {t.title}" + (f" ({due_str})" if due_str else "")
        )
    if tasks:
        lines.append(f"📋 Toplam {len(tasks)} bekleyen aksiyon")
    else:
        lines.append("✨ Bugün için bekleyen görevin yok.")

    rec_line = f"🎙️ {len(records)} ses kaydın"
    if total_words > 0:
        rec_line += f" · {total_words:,} kelime transkript"
    lines.append(rec_line)
    lines.append("")
    lines.append("Ne yapmak istersin?")

    return "\n".join(lines)


# ── CMD işleyicileri ──────────────────────────────────────────────────────────

def _cmd_greeting(db=None, user=None) -> dict:
    if db and user:
        msg = _greeting_msg(user, db)
    else:
        msg = "👋 VoiceToAction Asistanına hoş geldiniz!\n\nSize nasıl yardımcı olabilirim?"
    return {"answer": msg, "options": _MAIN_OPTIONS}


def _cmd_tasks(db, user) -> dict:
    tasks = (
        db.query(models.Task)
        .join(models.Record, models.Task.record_id == models.Record.id)
        .filter(models.Record.user_id == user.id)
        .order_by(models.Task.is_completed.asc(), models.Task.deadline.asc())
        .all()
    )
    if not tasks:
        return {"answer": "Henüz kayıtlı göreviniz yok.", "options": _MAIN_OPTIONS}
    lines = ["📋 Görevleriniz:\n"]
    for i, t in enumerate(tasks, 1):
        due = t.deadline.strftime("%d.%m.%Y") if t.deadline else "Tarih yok"
        icon = "✅" if t.is_completed else "⏳"
        lines.append(f"{i}. {icon} {t.title}  [{due}]")
    summary = _fmt_task_count(tasks)
    return {
        "answer": f"{summary}\n\n" + "\n".join(lines),
        "options": ["CMD_RECORDS", "CMD_MENU"],
    }


def _cmd_records(db, user) -> dict:
    records = (
        db.query(models.Record)
        .filter(models.Record.user_id == user.id)
        .order_by(models.Record.id.desc())
        .all()
    )
    if not records:
        return {"answer": "Henüz ses kaydınız yok.", "options": _MAIN_OPTIONS}
    lines = ["🎙️ Ses Kayıtlarınız:\n"]
    for r in records:
        cat = (r.category or "Diğer").strip()
        icon = "✔" if (r.transcribed_text or "").strip() else "✖"
        display_name = r.filename.rsplit(".", 1)[0] if r.filename else f"Kayıt {r.id}"
        lines.append(f"{icon} {cat} — {display_name}")
    lines.append("\nİşlem yapmak istediğiniz kaydı seçin:")
    select_opts = []
    for r in records[:5]:
        display = r.filename.rsplit(".", 1)[0] if r.filename else f"Kayıt {r.id}"
        select_opts.append(f"CMD_SELECT_{r.id}|{display}")
    return {
        "answer": "\n".join(lines),
        "options": select_opts + ["CMD_MENU"],
    }


def _cmd_select(record_id: int, db, user) -> dict:
    record = _get_record(record_id, user.id, db)
    if not record:
        return _no_record_resp(record_id)
    cat = (record.category or "Diğer").strip()
    fn = record.filename.rsplit(".", 1)[0] if record.filename else "Kayıt"
    if not (record.transcribed_text or "").strip():
        return {
            "answer": (
                f"✅ {fn} ({cat}) seçildi\n\n"
                "⚠️ Bu kaydın transkript metni henüz yok."
            ),
            "options": ["CMD_RECORDS", "CMD_MENU"],
        }
    return {
        "answer": f"✅ {fn} ({cat}) seçildi\n\nBu kayıtla ne yapmak istersiniz?",
        "options": _action_options(record_id),
    }


def _analyze_tone(text: str) -> str:
    """
    Metnin tonunu/duygusunu kural tabanlı analiz eder.
    Döner: emoji + etiket string
    """
    lower = text.lower()
    word_count = len(lower.split())

    stres_words  = {"zor","zaman","yetişemiyorum","yetiş","acil","hızlı",
                    "hemen","bitirmem","gerekiyor","lazım","şart","deadline"}
    sinav_words  = {"sınav","vize","final","quiz","bütünleme","soruları"}
    ders_words   = {"tanım","kavram","formül","teorem","kural","açıklama",
                    "örnek","konu","bölüm","ünite","öğren","anla"}
    toplanti_words = {"toplantı","karar","gündem","katılımcı","sunum",
                      "rapor","proje","ekip","takım","hedef"}
    pozitif_words = {"tamamlandı","bitti","başardık","iyi","güzel",
                     "harika","tamam","oldu","çözdük"}

    tokens = set(re.findall(r'[a-zçğışöü]+', lower))

    scores = {
        "stres":    len(tokens & stres_words),
        "sinav":    len(tokens & sinav_words),
        "ders":     len(tokens & ders_words),
        "toplanti": len(tokens & toplanti_words),
        "pozitif":  len(tokens & pozitif_words),
    }
    best = max(scores, key=lambda k: scores[k])

    if scores[best] == 0:
        if word_count > 300:
            return "🎓 **Ton:** Ders/Akademik içerik (uzun kayıt)"
        return "📝 **Ton:** Genel not"

    tone_map = {
        "stres":    "😰 **Ton:** Stresli / Acil — yaklaşan deadline olabilir",
        "sinav":    "📚 **Ton:** Sınav odaklı — kritik bilgiler içeriyor",
        "ders":     "🎓 **Ton:** Akademik ders içeriği",
        "toplanti": "💼 **Ton:** Toplantı / İş görüşmesi",
        "pozitif":  "✅ **Ton:** Pozitif / Tamamlayıcı",
    }
    return tone_map[best]


def _cmd_summarize(record_id: int, db, user) -> dict:
    record = _get_record(record_id, user.id, db)
    if not record:
        return _no_record_resp(record_id)
    text = (record.transcribed_text or "").strip()
    if not text:
        return _empty_transcript_resp(record_id)

    sentences = [s.strip() for s in re.split(r'[.!?]+', text) if len(s.strip()) > 10]
    word_count = len(text.split())
    tasks_in_record = db.query(models.Task).filter(
        models.Task.record_id == record_id).count()
    today = date.today()

    # ADIM 1: Cümleleri önem sırasına göre skorla
    def _rank_sent(sent: str) -> int:
        l = sent.lower()
        s = 0
        if _has_action_verb(l):         s += 3
        if _resolve_date(l, today):     s += 3
        if _is_reminder(l):             s += 3
        wc = len(sent.split())
        if 8 <= wc <= 20:               s += 2
        if not l.strip().endswith('?'): s += 1
        if _EXPLANATION_RE.search(l):   s -= 2
        if wc < 4:                      s -= 1
        return s

    # ADIM 2: En önemli 4 cümle, orijinal sırayla döndür
    indexed = list(enumerate(sentences))
    ranked_idx = sorted(indexed, key=lambda x: _rank_sent(x[1]), reverse=True)
    top4_indices = sorted([i for i, _ in ranked_idx[:4]])
    selected = [sentences[i] for i in top4_indices if i < len(sentences)]

    # ADIM 3: TF-IDF benzeri anahtar kelime (stop words filtreli, top 5)
    _STOP = {
        "bir","bu","şu","o","ve","ile","de","da","ki","mi","mu","mü","mı",
        "için","ama","fakat","çünkü","ya","veya","gibi","kadar","daha",
        "çok","az","en","ne","nasıl","neden","hangi","olan","olarak",
        "ise","bile","sadece","hem","var","yok",
        "ben","sen","biz","siz","onlar","bunu","buna","bunun","şunu",
        "yani","işte","zaten","tamam","peki","evet","hayır","şimdi","sonra","önce",
    }
    words_lower = re.findall(r'[a-zçğışöüA-ZÇĞİŞÖÜ]{4,}', text.lower())
    freq: dict[str, int] = {}
    for w in words_lower:
        if w not in _STOP:
            freq[w] = freq.get(w, 0) + 1
    top_keywords = sorted(freq.items(), key=lambda x: x[1], reverse=True)[:5]
    keyword_str = " · ".join(f"**{w}** ({c}x)" for w, c in top_keywords)

    # ADIM 4: İçerik tipi analizi
    def _analyze_emotion(t: str) -> str:
        l2 = t.lower()
        ws = set(re.findall(r'[a-zçğışöü]+', l2))
        scores = {
            "😰 Gergin":   len(ws & {"zor","acil","stres","panik","korku","endişe","kaygı","sıkıştı","bunaldım","yorgun","bitkin"}),
            "😊 Sakin":    len(ws & {"güzel","rahat","iyi","tamam","normal","sakin","anladım","öğrendim","keyifli"}),
            "💪 Motive":   len(ws & {"yapacağım","başlıyorum","hazırım","hedef","odaklan","çalış","başar","ilerliyorum","kararlı"}),
            "😕 Karmaşık": len(ws & {"anlamadım","karıştı","bilmiyorum","hata"}),
            "🔥 Heyecanlı":len(ws & {"harika","mükemmel","süper","inanılmaz","muhteşem","başardım","yaptım"}),
        }
        best = max(scores, key=lambda k: scores[k])
        if scores[best] == 0:
            return "😐 **Duygu Tonu:** Nötr"
        return f"**Duygu Tonu:** {best}"

    emotion = _analyze_emotion(text)
    kategori = (record.category or "Genel").strip()

    fn = record.filename.rsplit(".", 1)[0] if record.filename else f"Kayıt {record_id}"
    bullet_lines = (
        "\n".join(f"• {s}" for s in selected)
        if selected else "• (Yeterli içerik bulunamadı)"
    )

    answer = (
        f"📄 **{fn}**\n\n"
        f"📁 **Kategori:** {kategori}\n"
        f"{emotion}\n\n"
        f"**Ne konuşuldu:**\n"
        f"{bullet_lines}\n\n"
        f"🔑 **Öne Çıkan:** {keyword_str}\n"
        f"📊 {word_count} kelime · {len(sentences)} cümle · {tasks_in_record} aksiyon çıkarıldı"
    )
    return {
        "answer": answer,
        "options": [o for o in _action_options(record_id) if "SUMMARIZE" not in o],
    }


def _cmd_analyze(record_id: int, db, user) -> dict:
    record = _get_record(record_id, user.id, db)
    if not record:
        return _no_record_resp(record_id)
    text = (record.transcribed_text or "").strip()
    if not text:
        return _empty_transcript_resp(record_id)

    lower = text.lower()
    results = []

    sinav_pattern = re.compile(
        r'(?:sınav|vize|final|quiz|bütünleme)[^.!?]*(?:var|olacak|yapılacak|'
        r'[0-9]+\s*(?:mayıs|haziran|ocak|şubat|mart|nisan|temmuz|ağustos|eylül|ekim|kasım|aralık))',
        re.IGNORECASE | re.UNICODE
    )
    for m in sinav_pattern.finditer(lower):
        sentence = text[max(0, m.start()-20):m.end()+40].strip()
        results.append({"icerik": sentence[:80], "kategori": "Sınav Tarihi", "tarih": ""})

    odev_pattern = re.compile(
        r'(?:ödev|teslim|proje|sunum)[^.!?]*(?:yarın|bugün|haftaya|'
        r'pazartesi|salı|çarşamba|perşembe|cuma|[0-9]+\s*(?:gün|hafta))',
        re.IGNORECASE | re.UNICODE
    )
    for m in odev_pattern.finditer(lower):
        sentence = text[max(0, m.start()-20):m.end()+40].strip()
        results.append({"icerik": sentence[:80], "kategori": "Ödev/Görev", "tarih": ""})

    db_tasks = db.query(models.Task).filter(
        models.Task.record_id == record_id,
        models.Task.is_completed == False  # noqa: E712
    ).all()

    _CATEGORY_EMOJI = {
        "sınav tarihi": "📅", "ödev/görev": "📝", "sınav notu": "📌"
    }

    task_lines = []
    for item in results[:5]:
        emoji = _CATEGORY_EMOJI.get(item["kategori"].lower(), "📋")
        task_lines.append(f"{emoji} **{item['kategori']}:** {item['icerik']}")

    if not task_lines and db_tasks:
        for t in db_tasks[:5]:
            due = t.deadline.strftime("%d.%m") if t.deadline else "Tarih yok"
            task_lines.append(f"📋 {t.title} _(📅 {due})_")

    if task_lines:
        answer = "🎓 **Akademik Hatırlatmalar:**\n" + "\n".join(task_lines)
    else:
        answer = "Bu kayıtta önemli bir akademik hatırlatma bulunamadı."

    return {
        "answer": answer,
        "options": [o for o in _action_options(record_id) if "ANALYZE" not in o],
    }


def _cmd_calendar(record_id: int, db, user) -> dict:
    record = _get_record(record_id, user.id, db)
    if not record:
        return _no_record_resp(record_id)
    text = (record.transcribed_text or "").strip()
    if not text:
        return _empty_transcript_resp(record_id)

    display_name = record.filename.rsplit(".", 1)[0] if record.filename else f"Kayıt {record_id}"
    found = []

    # Gün + ay pattern: "15 mayıs", "3 haziran"
    gun_ay = re.findall(
        r'(\d{1,2})\s*(ocak|şubat|mart|nisan|mayıs|haziran|temmuz|ağustos|eylül|ekim|kasım|aralık)',
        text.lower(), re.UNICODE
    )
    for gun, ay in gun_ay:
        found.append(f"📅 {gun} {ay.capitalize()}")

    # Haftanın günleri
    gunler = re.findall(
        r'\b(pazartesi|salı|çarşamba|perşembe|cuma|cumartesi|pazar)\b',
        text.lower(), re.UNICODE
    )
    for g in set(gunler):
        found.append(f"📆 {g.capitalize()}")

    # Saat
    saatler = re.findall(r'saat\s*(\d{1,2}(?::\d{2})?)', text.lower())
    for s in set(saatler):
        found.append(f"🕐 Saat {s}")

    # Yakın zamanlı ifadeler
    if "yarın" in text.lower():
        found.append("⏰ Yarın")
    if "haftaya" in text.lower() or "gelecek hafta" in text.lower():
        found.append("📅 Gelecek hafta")
    if "bugün" in text.lower():
        found.append("📍 Bugün")

    # DB'deki görev tarihleri
    db_tasks = db.query(models.Task).filter(
        models.Task.record_id == record_id,
        models.Task.deadline.isnot(None)
    ).all()
    for t in db_tasks:
        found.append(f"✅ {t.title[:40]} → {t.deadline.strftime('%d %B %Y')}")

    if found:
        unique = list(dict.fromkeys(found))
        answer = f"📅 **Takvim — {display_name}**\n\n" + "\n".join(unique[:8])
    else:
        answer = f"📅 **{display_name}** kaydında tarih/saat bulunamadı."

    return {
        "answer": answer,
        "options": [o for o in _action_options(record_id) if "CALENDAR" not in o],
    }


def _cmd_meeting(record_id: int, db, user) -> dict:
    record = _get_record(record_id, user.id, db)
    if not record:
        return _no_record_resp(record_id)
    text = (record.transcribed_text or "").strip()
    if not text:
        return _empty_transcript_resp(record_id)

    sentences = [s.strip() for s in re.split(r'[.!?\n]+', text) if len(s.strip()) > 10]
    ltext = text.lower()

    # BÖLÜM 1: Ana konu tespiti
    _TOPIC_STOP = {
        "hafta","gün","saat","tarih","bugün","yarın","şimdi","zaman",
        "olan","gibi","daha","çok","var","yok","bir","bu","şu",
        "ama","ve","ile","de","da","ki","için","biz","ben","sen",
    }
    # Adım 1: "X dersi / X sınavı / X toplantısı" gibi açık konu adı ara
    _pattern_match = re.search(
        r'\b([\wçğışöüÇĞİŞÖÜ]+(?:\s+[\wçğışöüÇĞİŞÖÜ]+)?)\s+'
        r'(?:dersi|sınavı|toplantısı|ödevi|projesi|kursu)\b',
        ltext, re.IGNORECASE | re.UNICODE,
    )
    if _pattern_match:
        _detected = _pattern_match.group(1).strip()
        if _detected.lower() not in _TOPIC_STOP:
            konu_str = f"📚 **{record.category or 'Genel'}** — {_detected.capitalize()}"
        else:
            konu_str = f"📚 **{record.category or 'Genel'}**"
    else:
        konu_str = f"📚 **{record.category or 'Genel'}**"

    # BÖLÜM 2: Önemli bilgiler
    important: list[str] = []

    # Tanım/açıklama cümleleri
    def_re = re.compile(
        r'[\w\s\-çğışöüÇĞİŞÖÜ]{3,30}\s+'
        r'(?:nedir|şudur|olarak\s+tanımlanır|olarak\s+bilinir|ifade\s+eder)',
        re.IGNORECASE | re.UNICODE,
    )
    copula_re = re.compile(
        r'[\wçğışöüÇĞİŞÖÜ\s]{5,40}'
        r'(?:dir|dır|dur|dür|tır|tir|tur|tür)[\s.,]',
        re.IGNORECASE | re.UNICODE,
    )
    for sent in sentences:
        if def_re.search(sent) or copula_re.search(sent):
            important.append(sent[:120])
        if len(important) >= 3:
            break

    # Sayısal bilgi içeren cümleler
    for sent in sentences:
        if re.search(r'\d+', sent) and len(sent.split()) >= 5 and sent not in important:
            important.append(sent[:120])
        if len(important) >= 5:
            break

    # Yeterli içerik yoksa en uzun cümleleri al
    if len(important) < 2:
        for sent in sorted(sentences, key=len, reverse=True)[:3]:
            if sent not in important:
                important.append(sent[:120])

    important = important[:5]

    # BÖLÜM 3: Aksiyonlar
    normalized = _normalize_months(text)
    action_tasks = extract_tasks_from_text(normalized)

    # BÖLÜM 4: Tarihler/Deadlineler
    db_tasks_dated = db.query(models.Task).filter(
        models.Task.record_id == record_id,
        models.Task.deadline.isnot(None),
    ).all()

    # Çıktı oluştur
    lines = [
        "📝 **Ders/Toplantı Notu**",
        konu_str,
        "",
        "**📌 Önemli Noktalar:**",
    ]
    for info in important:
        lines.append(f"- {info}")

    if action_tasks:
        lines.append("")
        lines.append("**⚡ Aksiyonlar:**")
        for t in action_tasks[:4]:
            due = f" → {t['due_date']}" if t.get("due_date") else ""
            lines.append(f"- {t['task_title']}{due}")

    if db_tasks_dated:
        lines.append("")
        lines.append("**📅 Tarihler:**")
        for t in db_tasks_dated[:3]:
            due_str = t.deadline.strftime("%d.%m.%Y") if t.deadline else ""
            lines.append(f"- {due_str}: {t.title}")

    notes_text = "\n".join(lines)
    return {
        "answer": notes_text,
        "notes_text": notes_text,
        "record_id": record_id,
        "options": [o for o in _action_options(record_id) if "MEETING" not in o],
    }


def _cmd_exam(record_id: int, db, user) -> dict:
    """Metinden sınav hazırlık kartları (soru-cevap) üretir."""
    record = _get_record(record_id, user.id, db)
    if not record:
        return _no_record_resp(record_id)
    text = (record.transcribed_text or "").strip()
    if not text:
        return _empty_transcript_resp(record_id)

    sentences = [s.strip() for s in re.split(r'[.!?\n]+', text) if len(s.strip()) > 10]
    cards: list[dict] = []

    # Ana konu tespiti
    _STOP = {
        "bir","bu","şu","o","ve","ile","de","da","ki","mi","mu","mü","mı",
        "için","ama","fakat","ya","veya","gibi","kadar","daha","çok","az",
        "en","ne","nasıl","neden","olan","olarak","ise","bile","var","yok",
    }
    words_raw = re.findall(r'[a-zçğışöüA-ZÇĞİŞÖÜ]{5,}', text.lower())
    freq: dict[str, int] = {}
    for w in words_raw:
        if w not in _STOP:
            freq[w] = freq.get(w, 0) + 1
    top_word = sorted(freq.items(), key=lambda x: x[1], reverse=True)
    main_topic = top_word[0][0].capitalize() if top_word else (record.category or "Genel")

    # 1. Metindeki "X nedir?" soruları → direkt al, sonraki cümle cevap
    nedir_re = re.compile(
        r'[\w\s\-çğışöüÇĞİŞÖÜ]{3,40}\s+nedir\??',
        re.IGNORECASE | re.UNICODE,
    )
    for i, sent in enumerate(sentences):
        if len(cards) >= 5:
            break
        if nedir_re.search(sent):
            question = sent.strip()
            if not question.endswith('?'):
                question += '?'
            answer_text = sentences[i + 1].strip() if i + 1 < len(sentences) else "—"
            cards.append({"q": question, "a": answer_text[:150]})

    # 2. "X, Y'dir" tanım cümleleri → "X nedir? → Y'dir" formatı
    def_re = re.compile(
        r'^([\w\s\-çğışöüÇĞİŞÖÜ]{3,35}?)\s*,\s*'
        r'([\w\s\-çğışöüÇĞİŞÖÜ]{5,80}?)'
        r'(?:dir|dır|dur|dür|tır|tir|tur|tür)[.,\s]*$',
        re.IGNORECASE | re.UNICODE,
    )
    for sent in sentences:
        if len(cards) >= 5:
            break
        m = def_re.match(sent.strip())
        if m:
            term = m.group(1).strip()
            if len(term.split()) <= 4:
                question = f"{term[0].upper() + term[1:]} nedir?"
                if not any(c["q"].lower() == question.lower() for c in cards):
                    cards.append({"q": question, "a": sent.strip()[:150]})

    # 3. Büyük harf başlayan çok kelimeli terimler → soru üret
    if len(cards) < 5:
        term_re = re.compile(
            r'\b[A-ZÇĞİŞÖÜ][a-zçğışöüA-ZÇĞİŞÖÜ]{2,}'
            r'(?:\s+[A-ZÇĞİŞÖÜ][a-zçğışöüA-ZÇĞİŞÖÜ]{2,})+\b'
        )
        seen_terms: set[str] = set()
        for sent in sentences:
            for m in term_re.finditer(sent):
                term = m.group(0).strip()
                if term not in seen_terms and len(term.split()) <= 3:
                    seen_terms.add(term)
                    question = f"{term} kavramı nedir?"
                    if not any(c["q"].lower() == question.lower() for c in cards):
                        cards.append({"q": question, "a": sent.strip()[:150]})
                if len(cards) >= 5:
                    break
            if len(cards) >= 5:
                break

    if not cards:
        fn = record.filename.rsplit(".", 1)[0] if record.filename else f"Kayıt {record_id}"
        return {
            "answer": (
                f"🎓 **Sınav Hazırlık Kartları**\n"
                f"📚 Konu: {main_topic}\n\n"
                "Bu kayıtta kart oluşturacak tanım/kavram bulunamadı. "
                "Ders notu içerikli kayıtlarda daha iyi sonuç verir."
            ),
            "options": [o for o in _action_options(record_id) if "EXAM" not in o],
        }

    lines = [
        "🎓 **Sınav Hazırlık Kartları**",
        f"📚 Konu: {main_topic}",
        "",
    ]
    for i, card in enumerate(cards[:5], 1):
        lines.append(f"❓ **Soru {i}:** {card['q']}")
        lines.append(f"✅ **Cevap:** {card['a']}")
        lines.append("")

    return {
        "answer": "\n".join(lines).rstrip(),
        "options": [o for o in _action_options(record_id) if "EXAM" not in o],
    }


def _cmd_topics(record_id: int, db, user) -> dict:
    """
    Kullanıcının TÜM kayıtlarını tarar.
    Aynı anahtar kelime 2+ kayıtta geçiyorsa 'tekrar eden konu' sayar.
    """
    records = db.query(models.Record).filter(
        models.Record.user_id == user.id,
        models.Record.transcribed_text.isnot(None)
    ).all()

    if len(records) < 2:
        return {
            "answer": "📊 Konu analizi için en az 2 kayıt gerekli.",
            "options": ["CMD_RECORDS", "CMD_MENU"],
        }

    _STOP = {
        "bir","bu","şu","ve","ile","de","da","ki","için","ama","çünkü",
        "olan","gibi","kadar","daha","çok","nasıl","neden","var","yok"
    }

    record_keywords: dict[int, set[str]] = {}
    for r in records:
        words = set(re.findall(r'[a-zçğışöüA-ZÇĞİŞÖÜ]{5,}', r.transcribed_text.lower()))
        record_keywords[r.id] = words - _STOP

    all_words: list[str] = []
    for kws in record_keywords.values():
        all_words.extend(kws)
    word_record_count = Counter(all_words)
    repeated = [(w, c) for w, c in word_record_count.items() if c >= 2]
    repeated.sort(key=lambda x: x[1], reverse=True)

    if not repeated:
        return {
            "answer": "🔍 Kayıtlarında henüz tekrar eden bir konu bulunamadı.",
            "options": ["CMD_RECORDS", "CMD_MENU"],
        }

    top = repeated[:6]
    lines = [f"🔄 **{w}** — {c} kayıtta geçiyor" for w, c in top]

    sinav_tekrar = [w for w, _ in top if w in {"sınav","vize","final","ödev","teslim"}]
    uyari = ""
    if sinav_tekrar:
        uyari = f"\n\n⚠️ **'{sinav_tekrar[0]}'** birden fazla kayıtta geçiyor — yaklaşan bir deadline olabilir!"

    answer = (
        f"📊 **Tekrar Eden Konular ({len(records)} kayıt tarandı):**\n\n"
        + "\n".join(lines)
        + uyari
    )
    return {
        "answer": answer,
        "options": ["CMD_RECORDS", "CMD_MENU"],
    }


def _dispatch_cmd(cmd: str, db, user) -> dict:
    """CMD_ ile başlayan mesajları parse et ve ilgili handler'a yönlendir."""
    if cmd in ("CMD_MENU", "CMD_GREETING"):
        return _cmd_greeting(db, user)
    if cmd == "CMD_TASKS":
        return _cmd_tasks(db, user)
    if cmd == "CMD_RECORDS":
        return _cmd_records(db, user)

    m = re.match(r"^CMD_SELECT_(\d+)$", cmd)
    if m:
        return _cmd_select(int(m.group(1)), db, user)

    m = re.match(r"^CMD_SUMMARIZE_(\d+)$", cmd)
    if m:
        return _cmd_summarize(int(m.group(1)), db, user)

    m = re.match(r"^CMD_ANALYZE_(\d+)$", cmd)
    if m:
        return _cmd_analyze(int(m.group(1)), db, user)

    m = re.match(r"^CMD_CALENDAR_(\d+)$", cmd)
    if m:
        return _cmd_calendar(int(m.group(1)), db, user)

    m = re.match(r"^CMD_MEETING_(\d+)$", cmd)
    if m:
        return _cmd_meeting(int(m.group(1)), db, user)

    m = re.match(r"^CMD_TOPICS_(\d+)$", cmd)
    if m:
        return _cmd_topics(int(m.group(1)), db, user)

    m = re.match(r"^CMD_EXAM_(\d+)$", cmd)
    if m:
        return _cmd_exam(int(m.group(1)), db, user)

    print(f"[/api/chat] Bilinmeyen CMD: {cmd}")
    return {"answer": "Bilinmeyen komut.", "options": _MAIN_OPTIONS}


@app.post("/api/chat")
def chat(
    body: ChatRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """
    Deterministik asistan — CMD tabanlı routing (v5).
    Butonlar CMD kodu gönderir → sonsuz döngü imkansız.
    Serbest metin girişi eski fuzzy eşleşmeyle desteklenir.
    """
    msg = body.message.strip()
    low = msg.lower()
    print(f"[/api/chat] user={current_user.id} | mesaj='{msg}'")

    # ══════════════════════════════════════════════════════════════════════════
    # CMD ROUTING: Flutter butonlarından gelen kesin komutlar
    # Sonsuz döngü burada tamamen önlenir — kelime eşleştirmesi YOK.
    # ══════════════════════════════════════════════════════════════════════════
    if msg.startswith("CMD_"):
        print(f"[/api/chat] CMD routing: {msg}")
        return _dispatch_cmd(msg, db, current_user)

    # ══════════════════════════════════════════════════════════════════════════
    # SERBEST METİN FALLBACK — klavyeden yazılan girişler için fuzzy eşleştirme
    # ══════════════════════════════════════════════════════════════════════════
    words = set(low.split())

    # GREETING
    if not msg or words & _GREETING_WORDS or len(low) < 3:
        print("[/api/chat] FreeText: GREETING")
        return _cmd_greeting(db, current_user)

    # TASKS
    if any(k in low for k in ["görev", "yapılacak", "planım", "takvim"]):
        print("[/api/chat] FreeText: TASKS")
        return _cmd_tasks(db, current_user)

    # RECORDS
    if any(k in low for k in ["kayıt", "ses kayıt", "transkript", "ne konuştum"]):
        print("[/api/chat] FreeText: RECORDS")
        return _cmd_records(db, current_user)

    # FALLBACK
    print("[/api/chat] Durum: FALLBACK")
    return {
        "answer": (
            "🤔 Tam anlayamadım, ama yardımcı olmak istiyorum!\n\n"
            "Aşağıdaki butonları kullanabilirsin:"
        ),
        "options": _MAIN_OPTIONS,
    }