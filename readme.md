# 🎙️ Voice To Action 

**Voice To Action**, toplantı, ders ve röportaj kayıtlarını lokal yapay zeka modelleriyle analiz eden; sesten metne dönüşüm yapıp içerikten otomatik "görevler" ve "tarihler" çıkaran akıllı bir asistan ve EdTech projesidir.

## 🚀 Kullanılan Teknolojiler (Tech Stack)
- **Backend:** Python, FastAPI
- **Veritabanı:** PostgreSQL (SQLAlchemy)
- **Frontend (Web):** HTML5, CSS3, Vanilla JS (`map`, `filter`, `reduce` tabanlı fonksiyonel programlama)
- **Frontend (Mobil):** Flutter (Dart)
- **Yapay Zeka (Dış API Yok):** Whisper (Speech-to-Text), spaCy/NLTK (Kural Tabanlı NLP), FFMPEG, gTTS

---

## 📅 11 Haftalık İş Paketleri (Sprint Takvimi)

Aşağıdaki tablo, projenin Çevik (Agile) geliştirme sürecindeki haftalık hedeflerini göstermektedir. *(Test süreçleri 3. haftadan itibaren her pakete entegre edilmiştir.)*

| Hafta | Durum | İş Paketi (Kapsam) | Görevler / Detaylar |
| :---: | :---: | :--- | :--- |
| **1** | ✅ Bitti | **Sistem Analizi ve Arayüz Tasarımı** | • Gereksinim analizi dokümanının hazırlanması.<br>• Mobil ve web arayüz (UI/UX) taslaklarının çizilmesi. |
| **2** | ⏳ Bekliyor | **Veritabanı ve Backend Kurulumu** | • PostgreSQL tablolarının tasarlanması.<br>• FastAPI iskeletinin ayağa kaldırılması ve DB bağlantısı. |
| **3** | ⏳ Bekliyor | **API Uç Noktaları ve Güvenlik** | • JWT tabanlı kullanıcı doğrulama (Auth) sistemi.<br>• Ses/Video yükleme API'lerinin yazılması. |
| **4** | ⏳ Bekliyor | **Ön Yüz İskeletlerinin Kurulumu** | • Flutter yönlendirme (routing) iskeletinin kurulması.<br>• Web paneli statik HTML/CSS şablonları. |
| **5** | ⏳ Bekliyor | **Yapay Zeka Faz 1 (Sesten Metne)** | • FFMPEG ile videolardan ses ayrıştırma.<br>• Lokal Whisper modeli ile sesten metne dönüşüm. |
| **6** | ⏳ Bekliyor | **NLP Algoritması Faz 2 (Görev Çıkarma)**| • Kural tabanlı NLP algoritmasının (spaCy/NLTK) yazılması.<br>• Görev ve tarihlerin JSON olarak tespit edilmesi. |
| **7** | ⏳ Bekliyor | **Mobil Uygulama Veri Entegrasyonu** | • Flutter uygulamasının FastAPI sunucusuna bağlanması.<br>• Analizlerin dinamik kartlar halinde listelenmesi. |
| **8** | ⏳ Bekliyor | **Web Paneli Veri Analizi (FP)** | • Vanilla JS (`map`, `filter`, `reduce`) ile veri işleme.<br>• Analiz istatistiklerinin grafiklere dökülmesi. |
| **9** | ⏳ Bekliyor | **Gelişmiş Eğitim Modülleri & ChatBot**| • Kural tabanlı çoktan seçmeli test (Quiz) üretilmesi.<br>• Python TTS ile özet podcast dönüşümü.<br>• Soru-cevap modülünün eklenmesi. |
| **10** | ⏳ Bekliyor | **Testler ve Performans Optimizasyonu** | • Uçtan Uca (E2E) entegrasyon testlerinin yapılması.<br>• AI veri işleme hızının ve API'lerin optimize edilmesi. |
| **11** | ⏳ Bekliyor | **Dokümantasyon ve Final Sunumu** | • README dosyasının kullanım rehberine dönüştürülmesi.<br>• Final jüri sunumunun gerçekleştirilmesi. |