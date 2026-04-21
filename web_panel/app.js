/* =========================================================
   VoiceToAction — Web Panel  |  app.js
   Backend: http://127.0.0.1:8000
   ========================================================= */

const BASE_URL    = 'http://127.0.0.1:8000/api';
const USER_ID_KEY  = 'voice_action_user_id';
const USER_NAME_KEY = 'voice_action_user_name';
const TOKEN_KEY    = 'voice_action_token';      // JWT access token

// Grafik instance'ını dışarıda tutuyoruz: yeniden render'da destroy yapılacak
let myChart = null;

// Transkript modalı için kayıtları önbelleğe al
let _cachedRecords = [];

// Kategorilere renk atama haritası
const CATEGORY_COLORS = {
  'Eğitim':    '#2563EB',
  'Toplantı':  '#7C3AED',
  'Röportaj':  '#F59E0B',
  'Web-Upload':'#10B981',
  'Diğer':     '#6B7280',
  'genel':     '#6B7280',
};

// ─────────────────────────────────────────────────────────
// YARDIMCI: Geçerli JWT token'ını Authorization header olarak döner
// ─────────────────────────────────────────────────────────
function authHeaders() {
  const token = localStorage.getItem(TOKEN_KEY);
  return token ? { Authorization: `Bearer ${token}` } : {};
}

// ─────────────────────────────────────────────────────────
// YARDIMCI: 401 geldiğinde → oturumu kapat + hata göster
// ─────────────────────────────────────────────────────────
function handleUnauthorized() {
  console.warn('[auth] Token geçersiz veya süresi dolmuş. Logout yapılıyor.');
  logout();
  showLoginError('Oturumunuzun süresi doldu. Lütfen tekrar giriş yapın.');
}

// ─────────────────────────────────────────────────────────
// SAYFA YÜKLENDİĞİNDE — oturum kontrolü (token varlığına göre)
// ─────────────────────────────────────────────────────────
window.onload = () => {
  const token = localStorage.getItem(TOKEN_KEY);
  const userId = localStorage.getItem(USER_ID_KEY);
  if (token && userId) {
    showDashboard();
  }
};

// ─────────────────────────────────────────────────────────
// LOGIN
// Backend: POST /api/login — OAuth2PasswordRequestForm
// username + password  application/x-www-form-urlencoded
// ─────────────────────────────────────────────────────────
async function login() {
  const email    = document.getElementById('emailInput').value.trim();
  const password = document.getElementById('passwordInput').value;
  const errorEl  = document.getElementById('loginError');
  const btnText  = document.getElementById('loginBtnText');
  const btnIcon  = document.getElementById('loginBtnIcon');

  if (!email || !password) {
    showLoginError('E-posta ve şifre alanları boş bırakılamaz.');
    return;
  }

  // Yükleniyor göstergesi
  btnText.textContent = 'Giriş yapılıyor...';
  btnIcon.className = 'fa-solid fa-spinner fa-spin';
  errorEl.classList.add('hidden');

  // FastAPI OAuth2 form body (JSON DEĞİL — URLSearchParams)
  const formBody = new URLSearchParams();
  formBody.append('username', email);
  formBody.append('password', password);

  try {
    const response = await fetch(`${BASE_URL}/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: formBody,
    });

    if (response.ok) {
      const data = await response.json();

      // JWT token + kimlik bilgilerini localStorage'a kaydet
      localStorage.setItem(TOKEN_KEY,    data.access_token);
      localStorage.setItem(USER_ID_KEY,  String(data.user_id ?? data.id));
      if (data.full_name) {
        localStorage.setItem(USER_NAME_KEY, data.full_name);
      }

      errorEl.classList.add('hidden');
      showDashboard();
    } else {
      const err = await response.json().catch(() => ({}));
      showLoginError(err.detail || 'Hatalı e-posta veya şifre.');
    }
  } catch (e) {
    console.error('[login] Bağlantı hatası:', e);
    showLoginError('Sunucuya bağlanılamadı. Backend çalışıyor mu?');
  } finally {
    btnText.textContent = 'Giriş Yap';
    btnIcon.className = 'fa-solid fa-arrow-right';
  }
}

// ─────────────────────────────────────────────────────────
// FORM GEÇİŞLERİ — Login ↔ Kayıt Ol
// ─────────────────────────────────────────────────────────
function showRegisterForm() {
  document.getElementById('loginForm').classList.add('hidden');
  document.getElementById('registerForm').classList.remove('hidden');
  document.getElementById('authSubtitle').textContent = 'Yeni hesap oluşturun';
  document.getElementById('loginError').classList.add('hidden');
  document.getElementById('successMsg').classList.add('hidden');
  // Kayıt alanlarını temizle
  ['regFullName', 'regEmail', 'regPassword'].forEach(id => {
    document.getElementById(id).value = '';
  });
}

function showLoginForm() {
  document.getElementById('registerForm').classList.add('hidden');
  document.getElementById('loginForm').classList.remove('hidden');
  document.getElementById('authSubtitle').textContent = 'Hesabınıza giriş yapın';
  document.getElementById('loginError').classList.add('hidden');
  document.getElementById('successMsg').classList.add('hidden');
}

// ─────────────────────────────────────────────────────────
// KAYIT OL
// Backend: POST /api/register — JSON body
// ─────────────────────────────────────────────────────────
async function register() {
  const fullName = document.getElementById('regFullName').value.trim();
  const email    = document.getElementById('regEmail').value.trim();
  const password = document.getElementById('regPassword').value;
  const btnText  = document.getElementById('regBtnText');
  const btnIcon  = document.getElementById('regBtnIcon');

  // Doğrulama
  if (!fullName || !email || !password) {
    showLoginError('Tüm alanları doldurun.');
    return;
  }
  if (password.length < 6) {
    showLoginError('Şifre en az 6 karakter olmalıdır.');
    return;
  }

  btnText.textContent = 'Kayıt yapılıyor...';
  btnIcon.className   = 'fa-solid fa-spinner fa-spin text-sm';
  document.getElementById('loginError').classList.add('hidden');
  document.getElementById('successMsg').classList.add('hidden');

  try {
    // 1) Kayıt isteği — backend UserRegister (JSON) bekliyor
    const regRes = await fetch(`${BASE_URL}/register`, {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify({ full_name: fullName, email, password }),
    });

    if (!regRes.ok) {
      const err = await regRes.json().catch(() => ({}));
      showLoginError(err.detail || 'Kayıt başarısız. Bu e-posta zaten kayıtlı olabilir.');
      return;
    }

    console.log('[register] Hesap oluşturuldu. Otomatik giriş yapılıyor...');
    btnText.textContent = 'Giriş yapılıyor...';

    // 2) Otomatik giriş — kayıt başarılıysa hemen token al
    const loginBody = new URLSearchParams();
    loginBody.append('username', email);
    loginBody.append('password', password);

    const loginRes = await fetch(`${BASE_URL}/login`, {
      method:  'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body:    loginBody,
    });

    if (loginRes.ok) {
      const data = await loginRes.json();
      localStorage.setItem(TOKEN_KEY,    data.access_token);
      localStorage.setItem(USER_ID_KEY,  String(data.user_id ?? data.id));
      if (data.full_name) localStorage.setItem(USER_NAME_KEY, data.full_name);
      showDashboard();
    } else {
      // Kayıt tamam ama otomatik giriş başarısız → login formuna yönlendir
      showLoginForm();
      document.getElementById('emailInput').value = email;
      showSuccessMsg('Hesabınız oluşturuldu! Lütfen giriş yapın.');
    }
  } catch (e) {
    console.error('[register] Bağlantı hatası:', e);
    showLoginError('Sunucuya bağlanılamadı. Backend çalışıyor mu?');
  } finally {
    btnText.textContent = 'Kayıt Ol';
    btnIcon.className   = 'fa-solid fa-user-plus text-sm';
  }
}

function showLoginError(msg) {
  document.getElementById('successMsg').classList.add('hidden');
  document.getElementById('loginErrorText').textContent = msg;
  document.getElementById('loginError').classList.remove('hidden');
}

function showSuccessMsg(msg) {
  document.getElementById('loginError').classList.add('hidden');
  document.getElementById('successMsgText').textContent = msg;
  document.getElementById('successMsg').classList.remove('hidden');
}

// ─────────────────────────────────────────────────────────
// LOGOUT
// ─────────────────────────────────────────────────────────
function logout() {
  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(USER_ID_KEY);
  localStorage.removeItem(USER_NAME_KEY);

  if (myChart) { myChart.destroy(); myChart = null; }

  document.getElementById('dashboardScreen').classList.add('hidden');
  document.getElementById('loginScreen').classList.remove('hidden');
  document.getElementById('emailInput').value = '';
  document.getElementById('passwordInput').value = '';
}

// ─────────────────────────────────────────────────────────
// PANEL GÖSTERECİ
// ─────────────────────────────────────────────────────────
function showDashboard() {
  document.getElementById('loginScreen').classList.add('hidden');
  document.getElementById('dashboardScreen').classList.remove('hidden');

  const name    = localStorage.getItem(USER_NAME_KEY) || 'Kullanıcı';
  const initial = name.trim().charAt(0).toUpperCase();

  // Sidebar (her zaman DOM'da, masaüstü/mobil)
  document.getElementById('welcomeText').textContent = name;
  document.getElementById('userInitial').textContent = initial;

  // Yeni layout ek elementleri — güvenli güncelleme
  const welcomeMain   = document.getElementById('welcomeTextMain');
  const mobileInitial = document.getElementById('userInitialMobile');
  if (welcomeMain)   welcomeMain.textContent   = name;
  if (mobileInitial) mobileInitial.textContent = initial;

  fetchData();
}

// ─────────────────────────────────────────────────────────
// NAVİGASYON — sol menü bölüm geçişleri
// ─────────────────────────────────────────────────────────
const SECTION_NAMES = ['dashboard', 'tasks', 'records', 'stats'];

function showSection(name) {
  SECTION_NAMES.forEach(s => {
    const view = document.getElementById(`view-${s}`);
    const link = document.getElementById(`nav-${s}`);
    if (view) view.classList.toggle('hidden', s !== name);
    if (link) link.classList.toggle('active', s === name);
  });
}

// ─────────────────────────────────────────────────────────
// SEKMELER — Görevler / Transkriptler (Dashboard paneli)
// ─────────────────────────────────────────────────────────
function switchTab(tab) {
  const isTask = tab === 'tasks';
  document.getElementById('panelTasks').classList.toggle('hidden', !isTask);
  document.getElementById('panelTranscripts').classList.toggle('hidden', isTask);

  const active   = 'px-3 py-1.5 rounded-xl text-xs font-semibold bg-white text-primary shadow-sm transition';
  const inactive = 'px-3 py-1.5 rounded-xl text-xs font-semibold text-gray-400 transition';
  document.getElementById('tabTasks').className       = isTask ? active : inactive;
  document.getElementById('tabTranscripts').className = isTask ? inactive : active;
}

// ─────────────────────────────────────────────────────────
// TRANSKRİPT MODALİ — aç / kapat
// ─────────────────────────────────────────────────────────
function openModal(idx) {
  const r = _cachedRecords[idx];
  if (!r) return;
  document.getElementById('modalTitle').textContent = r.file_name || 'Kayıt';
  document.getElementById('modalMeta').textContent  = r.category  || 'Diğer';
  document.getElementById('modalText').textContent  =
    (r.transcript && r.transcript.trim())
      ? r.transcript
      : 'Bu kayıt için transkript mevcut değil.';
  document.getElementById('transcriptModal').classList.remove('hidden');
  document.body.style.overflow = 'hidden';
}

function closeModal() {
  document.getElementById('transcriptModal').classList.add('hidden');
  document.body.style.overflow = '';
}

// ─────────────────────────────────────────────────────────
// VERİ ÇEKME — Shared State (Mobil ↔ Web aynı DB)
// ─────────────────────────────────────────────────────────
async function fetchData() {
  const userId = localStorage.getItem(USER_ID_KEY);
  if (!userId) { logout(); return; }

  // Yükleniyor durumu
  const refreshBtn = document.getElementById('refreshBtn');
  const tasksLoading = document.getElementById('tasksLoading');
  refreshBtn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Yükleniyor';
  tasksLoading.classList.remove('hidden');
  document.getElementById('tasksContainer').innerHTML = '';

  const headers = authHeaders();   // JWT Bearer token

  try {
    // Promise.all ile her iki endpoint'e eşzamanlı JWT'li istek
    const [recordsRes, tasksRes] = await Promise.all([
      fetch(`${BASE_URL}/records/${userId}`, { headers }),
      fetch(`${BASE_URL}/tasks/${userId}`,   { headers }),
    ]);

    // 401 → token geçersiz, oturumu kapat
    if (recordsRes.status === 401 || tasksRes.status === 401) {
      handleUnauthorized();
      return;
    }

    if (!recordsRes.ok || !tasksRes.ok) {
      throw new Error(`HTTP ${recordsRes.status} / ${tasksRes.status}`);
    }

    const records = await recordsRes.json();
    const tasks   = await tasksRes.json();

    console.log(`[fetchData] ${records.length} kayıt, ${tasks.length} görev alındı.`);

    // ── Fonksiyonel Programlama ──────────────────────────
    //
    // 1) FILTER — başlığı olan geçerli görevleri süz
    const validTasks = tasks.filter(
      t => t.title && t.title.trim().length > 2
    );

    // 2) FILTER (ikinci kullanım) — bekleyen (pending) görevleri say
    const pendingTasks = validTasks.filter(t => t.status !== 'done');

    // 3) REDUCE — kategorilere göre kayıt sayısı hesapla
    const categoryCounts = records.reduce((acc, r) => {
      const cat = r.category || 'Diğer';
      acc[cat] = (acc[cat] || 0) + 1;
      return acc;
    }, {});

    // 4) MAP — record_id → {transcript, file_name} arama tablosu
    //         Her görev kartına kaynak transkripti bağlamak için
    const recordTranscriptMap = records.reduce((acc, r) => {
      acc[r.id] = { transcript: r.transcript || '', file_name: r.file_name || '' };
      return acc;
    }, {});

    // 5) MAP — görev kartı HTML'ini transkript bağlamıyla birlikte üret
    const taskHtml = validTasks.map(t => {
      const isDone    = t.status === 'done';
      const dateLabel = t.due_date || 'Tarih belirtilmedi';
      const badgeCls  = isDone
        ? 'bg-emerald-50 text-emerald-600'
        : 'bg-amber-50 text-amber-600';
      const badgeTxt  = isDone ? 'Tamamlandı' : 'Bekliyor';
      const iconCls   = isDone
        ? 'fa-circle-check text-emerald-500'
        : 'fa-circle-dot text-primary';

      // Görevin çıkarıldığı kaydın transkript önizlemesi
      const rec     = recordTranscriptMap[t.record_id];
      const excerpt = rec && rec.transcript
        ? (rec.transcript.length > 72
            ? rec.transcript.substring(0, 72) + '…'
            : rec.transcript)
        : null;

      return `
        <div class="flex items-start gap-4 px-5 py-3.5 hover:bg-slate-50/80 transition-colors">
          <div class="w-9 h-9 rounded-2xl bg-primary-light flex items-center
                      justify-center flex-shrink-0 mt-0.5">
            <i class="fa-solid ${iconCls} text-sm"></i>
          </div>
          <div class="flex-1 min-w-0">
            <p class="text-sm font-semibold text-gray-800 leading-snug truncate">
              ${escHtml(t.title)}
            </p>
            <p class="text-[11px] text-gray-400 mt-0.5">
              <i class="fa-regular fa-calendar mr-1"></i>${escHtml(dateLabel)}
            </p>
            ${excerpt
              ? `<p class="text-[10px] text-gray-300 mt-1 truncate italic leading-snug">
                   <i class="fa-solid fa-quote-left text-[8px] mr-1"></i>${escHtml(excerpt)}
                 </p>`
              : ''}
          </div>
          <span class="text-[10px] font-semibold px-2.5 py-1 rounded-full
                       flex-shrink-0 ${badgeCls}">
            ${badgeTxt}
          </span>
        </div>`;
    }).join('');

    // 6) MAP — görev çıkarılmayan ama transkripti olan kayıtlar
    //         → "Analiz Edilen Metin" kartları olarak göster
    const recordsWithTasks = new Set(tasks.map(t => t.record_id));
    const analyzedOnlyHtml = records
      .filter(r => !recordsWithTasks.has(r.id) && r.transcript && r.transcript.trim())
      .map(r => {
        const idx     = records.indexOf(r);
        const excerpt = r.transcript.length > 90
          ? r.transcript.substring(0, 90) + '…'
          : r.transcript;
        return `
          <div class="flex items-start gap-4 px-5 py-3.5 hover:bg-slate-50/60 transition-colors">
            <div class="w-9 h-9 rounded-2xl bg-slate-100 flex items-center
                        justify-center flex-shrink-0 mt-0.5">
              <i class="fa-solid fa-file-waveform text-slate-400 text-sm"></i>
            </div>
            <div class="flex-1 min-w-0">
              <p class="text-[10px] font-bold text-gray-400 uppercase tracking-wider mb-0.5">
                Analiz Edilen Metin
              </p>
              <p class="text-sm text-gray-600 leading-snug truncate">${escHtml(excerpt)}</p>
              <p class="text-[11px] text-gray-300 mt-0.5">${escHtml(r.file_name)}</p>
            </div>
            <button onclick="openModal(${idx})"
              class="flex-shrink-0 text-xs font-semibold text-gray-400
                     hover:text-primary hover:bg-primary-light px-2.5 py-1 rounded-xl transition">
              Detay
            </button>
          </div>`;
      }).join('');

    // Ayırıcı başlık (her iki bölüm de doluysa)
    const sectionDivider = taskHtml && analyzedOnlyHtml
      ? `<div class="px-5 py-2.5 bg-slate-50 border-y border-slate-100">
           <p class="text-[10px] font-semibold text-gray-400 uppercase tracking-wider">
             <i class="fa-solid fa-file-waveform mr-1.5"></i>Görev Çıkarılmayan Kayıtlar
           </p>
         </div>`
      : '';

    const combinedHtml = taskHtml + sectionDivider + analyzedOnlyHtml;

    // ── DOM Güncelle ─────────────────────────────────────
    _cachedRecords = records;   // modal için önbellek

    document.getElementById('totalRecords').textContent = records.length;
    document.getElementById('totalTasks').textContent   = tasks.length;
    document.getElementById('pendingTasks').textContent = pendingTasks.length;

    document.getElementById('tasksContainer').innerHTML = combinedHtml ||
      `<div class="flex flex-col items-center py-14 gap-3">
         <i class="fa-solid fa-list-check text-gray-200 text-4xl"></i>
         <p class="text-sm text-gray-400 font-medium">Henüz görev tespit edilmedi.</p>
         <p class="text-xs text-gray-300">Bir ses yükleyin ve AI analiz etsin.</p>
       </div>`;

    renderChart(categoryCounts, records.length);

    // ── Yeni view'ları doldur ─────────────────────────────
    renderTranscripts(records);
    renderRecordsList(records);
    renderAllTasks(validTasks, tasks);
    renderStatsView(records, tasks, validTasks, pendingTasks, categoryCounts);

  } catch (e) {
    console.error('[fetchData] Hata:', e);
    document.getElementById('tasksContainer').innerHTML =
      `<p class="p-8 text-center text-red-400 text-sm font-medium">
         <i class="fa-solid fa-triangle-exclamation mr-1"></i>
         Veri yüklenemedi: ${escHtml(e.message)}
       </p>`;
  } finally {
    tasksLoading.classList.add('hidden');
    refreshBtn.innerHTML = '<i class="fa-solid fa-rotate-right"></i> Yenile';
  }
}

// ─────────────────────────────────────────────────────────
// DOSYA YÜKLEME (Drag & Drop + Click)
// ─────────────────────────────────────────────────────────
function handleDrop(event) {
  event.preventDefault();
  document.getElementById('dropZone').classList.remove('dragover');
  const file = event.dataTransfer.files[0];
  if (file) uploadFile(file);
}

async function uploadFile(fileOverride) {
  const statusEl  = document.getElementById('uploadStatus');
  const statusTxt = document.getElementById('uploadStatusText');
  const spinner   = document.getElementById('uploadSpinner');
  const inner     = document.getElementById('uploadStatusInner');
  const fileInput = document.getElementById('fileInput');

  const file  = fileOverride || fileInput.files[0];
  const token = localStorage.getItem(TOKEN_KEY);

  // Token yoksa kullanıcıyı login ekranına gönder
  if (!file) return;
  if (!token) { handleUnauthorized(); return; }

  // user_id artık FormData'ya eklenmez — backend kimliği JWT'den okuyor
  const formData = new FormData();
  formData.append('file', file);
  formData.append('category', 'Web-Upload');

  // Yükleniyor UI
  statusEl.classList.remove('hidden');
  inner.className = 'flex items-center gap-3 p-3 bg-blue-50 rounded-xl border border-blue-100';
  spinner.classList.remove('hidden');
  statusTxt.textContent = `"${escHtml(file.name)}" analiz ediliyor...`;
  statusTxt.className   = 'text-xs font-bold text-primary';

  try {
    const response = await fetch(`${BASE_URL}/transcribe`, {
      method: 'POST',
      headers: authHeaders(),   // Authorization: Bearer <token>
      body: formData,
    });

    // 401 → oturumu kapat
    if (response.status === 401) {
      handleUnauthorized();
      return;
    }

    if (response.ok) {
      const data = await response.json();
      const taskCount = (data.tasks || []).length;

      // Başarı UI
      spinner.classList.add('hidden');
      inner.className = 'flex items-center gap-3 p-3 bg-emerald-50 rounded-xl border border-emerald-100';
      statusTxt.textContent = `Tamamlandı! ${taskCount} görev tespit edildi.`;
      statusTxt.className   = 'text-xs font-bold text-emerald-600';

      setTimeout(() => {
        statusEl.classList.add('hidden');
        fileInput.value = '';
        fetchData();   // Listeyi güncelle
      }, 2500);
    } else {
      const err = await response.json().catch(() => ({}));
      throw new Error(err.detail || `HTTP ${response.status}`);
    }
  } catch (e) {
    console.error('[uploadFile] Hata:', e);
    spinner.classList.add('hidden');
    inner.className = 'flex items-center gap-3 p-3 bg-red-50 rounded-xl border border-red-100';
    statusTxt.textContent = `Yükleme başarısız: ${e.message}`;
    statusTxt.className   = 'text-xs font-bold text-red-500';
    setTimeout(() => statusEl.classList.add('hidden'), 4000);
  }
}

// ─────────────────────────────────────────────────────────
// RENDER — Transkriptler sekmesi (Dashboard paneli)
// ─────────────────────────────────────────────────────────
function renderTranscripts(records) {
  const container = document.getElementById('transcriptsContainer');
  if (!container) return;

  // Sadece transcript'i olan kayıtları göster
  const withTranscript = records.filter(r => r.transcript && r.transcript.trim());

  if (!withTranscript.length) {
    container.innerHTML = `
      <div class="py-12 flex flex-col items-center gap-3">
        <i class="fa-solid fa-file-waveform text-slate-200 text-4xl"></i>
        <p class="text-sm text-gray-300 font-medium">Henüz transkript yok</p>
        <p class="text-xs text-gray-300">Ses dosyası yükleyin, Whisper analiz etsin.</p>
      </div>`;
    return;
  }

  // withTranscript içindeki index'i _cachedRecords üzerinden al
  container.innerHTML = withTranscript.map(r => {
    const i     = records.indexOf(r);
    const color   = CATEGORY_COLORS[r.category] ?? '#6B7280';
    // API alanı: transcript (backend alias → r.transcribed_text)
    const preview = r.transcript.length > 130
      ? r.transcript.substring(0, 130) + '…'
      : r.transcript;

    return `
      <div class="px-5 py-4 hover:bg-slate-50/80 transition-colors">
        <div class="flex items-start gap-3">
          <div class="w-9 h-9 rounded-2xl bg-blue-50 flex items-center justify-center flex-shrink-0 mt-0.5">
            <i class="fa-solid fa-file-waveform text-primary text-sm"></i>
          </div>
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2 mb-1">
              <p class="text-xs font-semibold text-gray-800 truncate">${escHtml(r.file_name)}</p>
              <span class="text-[9px] font-bold px-2 py-0.5 rounded-full flex-shrink-0"
                style="background:${color}18; color:${color}">
                ${escHtml(r.category)}
              </span>
            </div>
            <p class="text-xs text-gray-400 leading-relaxed">${escHtml(preview)}</p>
          </div>
          <button onclick="openModal(${i})"
            class="flex-shrink-0 text-xs font-semibold text-primary hover:bg-primary-light
                   px-2.5 py-1 rounded-xl transition ml-1">
            Detay
          </button>
        </div>
      </div>`;
  }).join('');
}

// ─────────────────────────────────────────────────────────
// RENDER — Ses Kayıtları view (kart + Detay butonu)
// ─────────────────────────────────────────────────────────
function renderRecordsList(records) {
  const container = document.getElementById('recordsListContainer');
  const badge     = document.getElementById('recordsCountBadge');
  if (!container) return;

  // Transcript'i olan kayıtları öne al; olmayanlar grileştirilmiş olarak sona
  const sorted = [
    ...records.filter(r => r.transcript && r.transcript.trim()),
    ...records.filter(r => !r.transcript || !r.transcript.trim()),
  ];

  if (badge) badge.textContent = `${records.length} kayıt · ${sorted.filter(r => r.transcript).length} transkript`;

  if (!sorted.length) {
    container.innerHTML = `
      <div class="py-14 flex flex-col items-center gap-3">
        <i class="fa-solid fa-microphone-slash text-slate-200 text-4xl"></i>
        <p class="text-sm text-gray-300 font-medium">Henüz ses kaydı yok</p>
      </div>`;
    return;
  }

  container.innerHTML = sorted.map(r => {
    // Modal index için _cachedRecords (= records) üzerinden bul
    const i             = records.indexOf(r);
    const color         = CATEGORY_COLORS[r.category] ?? '#6B7280';
    // API alanı: transcript (r.transcribed_text'in alias'ı)
    const hasTranscript = !!(r.transcript && r.transcript.trim());
    const preview       = hasTranscript
      ? (r.transcript.length > 160 ? r.transcript.substring(0, 160) + '…' : r.transcript)
      : 'Bu kayıt için henüz transkript oluşturulmadı.';

    const statusBadge = hasTranscript
      ? `<span class="text-[9px] font-bold px-2 py-0.5 rounded-full bg-emerald-50 text-emerald-600">
           <i class="fa-solid fa-circle-check mr-0.5"></i>Transkript hazır
         </span>`
      : `<span class="text-[9px] font-bold px-2 py-0.5 rounded-full bg-amber-50 text-amber-500">
           <i class="fa-solid fa-clock mr-0.5"></i>Transkript yok
         </span>`;

    return `
      <div class="px-5 py-4 hover:bg-slate-50/60 transition-colors ${!hasTranscript ? 'opacity-60' : ''}">
        <div class="flex items-start gap-4">
          <div class="w-10 h-10 rounded-2xl flex items-center justify-center flex-shrink-0 mt-0.5"
            style="background:${color}18">
            <i class="fa-solid fa-waveform-lines text-sm" style="color:${color}"></i>
          </div>
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2 flex-wrap mb-1.5">
              <p class="text-sm font-semibold text-gray-800 truncate max-w-[200px]">
                ${escHtml(r.file_name)}
              </p>
              <span class="text-[10px] font-bold px-2.5 py-0.5 rounded-full flex-shrink-0"
                style="background:${color}18; color:${color}">
                ${escHtml(r.category)}
              </span>
              ${statusBadge}
            </div>
            <p class="text-xs ${hasTranscript ? 'text-gray-600' : 'text-gray-300 italic'} leading-relaxed">
              ${escHtml(preview)}
            </p>
          </div>
          ${hasTranscript
            ? `<button onclick="openModal(${i})"
                class="flex-shrink-0 flex items-center gap-1.5 text-xs font-semibold text-primary
                       hover:bg-primary-light border border-primary/20 px-3 py-1.5 rounded-xl transition">
                 <i class="fa-solid fa-expand text-[10px]"></i> Detay
               </button>`
            : `<span class="flex-shrink-0 text-[10px] text-gray-300 px-2">—</span>`}
        </div>
      </div>`;
  }).join('');
}

// ─────────────────────────────────────────────────────────
// RENDER — Görevlerim view (sınırsız tam liste)
// ─────────────────────────────────────────────────────────
function renderAllTasks(validTasks) {
  const container = document.getElementById('allTasksContainer');
  const badge     = document.getElementById('allTasksBadge');
  if (!container) return;

  // Bekleyenler önce, tamamlananlar sona
  const sorted = [
    ...validTasks.filter(t => t.status !== 'done'),
    ...validTasks.filter(t => t.status === 'done'),
  ];

  if (badge) badge.textContent = `${validTasks.length} görev · ${validTasks.filter(t => t.status !== 'done').length} bekliyor`;

  if (!sorted.length) {
    container.innerHTML = `
      <div class="py-14 flex flex-col items-center gap-3">
        <i class="fa-solid fa-list-check text-slate-200 text-4xl"></i>
        <p class="text-sm text-gray-300 font-medium">Henüz görev tespit edilmedi</p>
        <p class="text-xs text-gray-300">Bir ses yükleyin ve AI analiz etsin.</p>
      </div>`;
    return;
  }

  // _cachedRecords üzerinden transkript önizlemesini çek
  const recMap = _cachedRecords.reduce((acc, r) => {
    acc[r.id] = r;
    return acc;
  }, {});

  container.innerHTML = sorted.map(t => {
    const isDone    = t.status === 'done';
    const dateLabel = t.due_date || 'Tarih belirtilmedi';
    const badgeCls  = isDone ? 'bg-emerald-50 text-emerald-600' : 'bg-amber-50 text-amber-500';
    const badgeTxt  = isDone ? 'Tamamlandı' : 'Bekliyor';
    const dotCls    = isDone ? 'bg-emerald-400' : 'bg-amber-400';

    // Kaynak kaydın transkript önizlemesi
    const srcRecord = recMap[t.record_id];
    const srcFile   = srcRecord ? srcRecord.file_name : null;
    const srcExcerpt = srcRecord && srcRecord.transcript
      ? (srcRecord.transcript.length > 70
          ? srcRecord.transcript.substring(0, 70) + '…'
          : srcRecord.transcript)
      : null;

    return `
      <div class="px-5 py-4 hover:bg-slate-50/80 transition-colors">
        <div class="flex items-start justify-between gap-3">
          <div class="flex items-start gap-3 min-w-0 flex-1">
            <div class="w-2 h-2 rounded-full mt-2 flex-shrink-0 ${dotCls}"></div>
            <div class="min-w-0 flex-1">
              <p class="text-sm font-semibold text-gray-800 ${isDone ? 'line-through text-gray-400' : ''}">
                ${escHtml(t.title)}
              </p>
              <p class="text-xs text-gray-400 mt-0.5">
                <i class="fa-regular fa-calendar mr-1 text-[10px]"></i>${escHtml(dateLabel)}
              </p>
              ${srcFile
                ? `<p class="text-[10px] text-gray-300 mt-0.5">
                     <i class="fa-solid fa-microphone text-[8px] mr-1"></i>${escHtml(srcFile)}
                   </p>`
                : ''}
              ${srcExcerpt
                ? `<p class="text-[10px] text-gray-300 mt-0.5 truncate italic">
                     <i class="fa-solid fa-quote-left text-[8px] mr-1"></i>${escHtml(srcExcerpt)}
                   </p>`
                : ''}
            </div>
          </div>
          <span class="text-[10px] font-bold px-2.5 py-1 rounded-full flex-shrink-0 ${badgeCls}">
            ${badgeTxt}
          </span>
        </div>
      </div>`;
  }).join('');
}

// ─────────────────────────────────────────────────────────
// RENDER — İstatistikler view (sayılar + kategori çubukları)
// ─────────────────────────────────────────────────────────
function renderStatsView(records, allTasks, validTasks, pendingTasks, categoryCounts) {
  const setEl = (id, val) => { const el = document.getElementById(id); if (el) el.textContent = val; };
  const doneTasks = validTasks.filter(t => t.status === 'done');

  setEl('statTotalRecords', records.length);
  setEl('statTotalTasks',   allTasks.length);
  setEl('statPendingTasks', pendingTasks.length);
  setEl('statDoneTasks',    doneTasks.length);

  const list = document.getElementById('statsCategoryList');
  if (!list) return;

  const entries = Object.entries(categoryCounts);
  if (!entries.length) {
    list.innerHTML = `<p class="text-sm text-gray-300 text-center py-6">Henüz veri yok</p>`;
    return;
  }

  const total = records.length || 1;
  list.innerHTML = entries.map(([cat, count]) => {
    const color = CATEGORY_COLORS[cat] ?? '#6B7280';
    const pct   = Math.round((count / total) * 100);
    return `
      <div>
        <div class="flex items-center justify-between mb-1">
          <div class="flex items-center gap-2">
            <span class="w-2.5 h-2.5 rounded-full flex-shrink-0" style="background:${color}"></span>
            <span class="text-xs font-semibold text-gray-700">${escHtml(cat)}</span>
          </div>
          <span class="text-xs font-bold text-gray-500">${count} kayıt · ${pct}%</span>
        </div>
        <div class="h-1.5 bg-slate-100 rounded-full overflow-hidden">
          <div class="h-full rounded-full transition-all duration-700"
            style="width:${pct}%; background:${color}"></div>
        </div>
      </div>`;
  }).join('');
}

// ─────────────────────────────────────────────────────────
// GRAFİK — Chart.js Doughnut
// ─────────────────────────────────────────────────────────
function renderChart(categoryCounts, totalRecords) {
  const canvas   = document.getElementById('categoryChart');
  const emptyEl  = document.getElementById('chartEmpty');
  const centerEl = document.getElementById('chartCenter');
  const legendEl = document.getElementById('chartLegend');

  document.getElementById('chartTotalNum').textContent = totalRecords;

  const labels = Object.keys(categoryCounts);
  const values = Object.values(categoryCounts);

  if (labels.length === 0) {
    canvas.classList.add('hidden');
    centerEl.classList.add('hidden');
    emptyEl.classList.remove('hidden');
    legendEl.innerHTML = '';
    return;
  }

  canvas.classList.remove('hidden');
  centerEl.classList.remove('hidden');
  emptyEl.classList.add('hidden');

  const bgColors = labels.map(
    l => CATEGORY_COLORS[l] ?? `hsl(${(labels.indexOf(l) * 67) % 360}, 65%, 55%)`
  );

  if (myChart) myChart.destroy();

  myChart = new Chart(canvas.getContext('2d'), {
    type: 'doughnut',
    data: {
      labels,
      datasets: [{
        data: values,
        backgroundColor: bgColors,
        borderWidth: 4,
        borderColor: '#ffffff',      // beyaz arka planla kaynaşan kenarlık
        hoverBorderWidth: 5,
        hoverOffset: 4,
      }],
    },
    options: {
      cutout: '74%',
      layout: { padding: 4 },
      plugins: {
        legend: { display: false },
        tooltip: {
          backgroundColor: '#1e293b',
          titleFont: { family: 'Inter', size: 11, weight: '600' },
          bodyFont:  { family: 'Inter', size: 11 },
          padding: 10,
          cornerRadius: 10,
          callbacks: {
            label: ctx => `  ${ctx.label}: ${ctx.parsed} kayıt`,
          },
        },
      },
      animation: { animateScale: true, duration: 500, easing: 'easeOutQuart' },
    },
  });

  // Custom legend
  legendEl.innerHTML = labels.map((label, i) => `
    <span class="flex items-center gap-1.5 text-xs font-semibold text-gray-600">
      <span class="w-2.5 h-2.5 rounded-full inline-block flex-shrink-0" style="background:${bgColors[i]}"></span>
      ${escHtml(label)} (${values[i]})
    </span>
  `).join('');
}

// ─────────────────────────────────────────────────────────
// YARDIMCI: XSS koruması — kullanıcı verisini HTML'e basmadan önce temizle
// ─────────────────────────────────────────────────────────
function escHtml(str) {
  if (str == null) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}
