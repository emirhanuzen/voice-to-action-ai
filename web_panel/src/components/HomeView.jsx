import { useState, useRef, useEffect } from 'react';
import { motion } from 'framer-motion';
import { Mic, Zap, CheckCircle, Flame, RefreshCw, FolderOpen, Upload, AlertTriangle, Clock, CalendarClock } from 'lucide-react';
import api from '../api';

export default function HomeView({ records, tasks, loading, onRefresh, onNavigate }) {
  const [selectedRecord, setSelectedRecord] = useState(null);
  const [recording, setRecording] = useState(false);
  const [mediaRecorder, setMediaRecorder] = useState(null);
  const [uploadMsg, setUploadMsg] = useState('');
  const [uploadCategory, setUploadCategory] = useState('Eğitim');
  const [activeCategory, setActiveCategory] = useState('Tümü');
  const [noteText, setNoteText] = useState('');
  const [noteSaved, setNoteSaved] = useState(false);
  const fileRef = useRef();
  const [audioUrl, setAudioUrl] = useState(null);
  const [playing, setPlaying] = useState(false);
  const audioRef = useRef();
  const userName = localStorage.getItem('userName') || 'Kullanıcı';

  const loadNote = (recordId) => {
    const stored = JSON.parse(localStorage.getItem('voiceaction_notes') || '{}');
    return stored[recordId] || '';
  };

  const saveNote = () => {
    if (!selectedRecord || !noteText.trim()) return;
    const stored = JSON.parse(localStorage.getItem('voiceaction_notes') || '{}');
    stored[selectedRecord.id] = noteText;
    localStorage.setItem('voiceaction_notes', JSON.stringify(stored));
    setNoteSaved(true);
    setTimeout(() => setNoteSaved(false), 2000);
  };

  useEffect(() => {
    if (selectedRecord) setNoteText(loadNote(selectedRecord.id));
  }, [selectedRecord]);

  useEffect(() => {
    if (selectedRecord) {
      setAudioUrl(`http://localhost:8000/api/records/${selectedRecord.id}/audio`);
      setPlaying(false);
    }
  }, [selectedRecord]);

  const pending = tasks.filter(t => t.status !== 'done');
  const done = tasks.filter(t => t.status === 'done');
  const urgent = pending.filter(t => {
    if (!t.due_date) return false;
    const diff = (new Date(t.due_date) - new Date()) / (1000 * 60 * 60 * 24);
    return diff <= 2;
  });

  const categories = ['Tümü', 'Eğitim', 'Toplantı', 'Röportaj', 'Diğer'];
  const categoryColors = {
    'Eğitim':   'from-blue-600/20 to-blue-900/20 border-blue-500/30 text-blue-400',
    'Toplantı': 'from-purple-600/20 to-purple-900/20 border-purple-500/30 text-purple-400',
    'Röportaj': 'from-amber-600/20 to-amber-900/20 border-amber-500/30 text-amber-400',
    'Diğer':    'from-slate-600/20 to-slate-900/20 border-slate-500/30 text-slate-400',
    'Tümü':     'from-indigo-600/20 to-indigo-900/20 border-indigo-500/30 text-indigo-400',
  };

  const filteredRecords = activeCategory === 'Tümü'
    ? records
    : records.filter(r => r.category === activeCategory);

  const handleUpload = async (file) => {
    if (!file) return;
    setUploadMsg('⏳ Analiz ediliyor...');
    try {
      const data = await api.uploadAudio(file, uploadCategory);
      if (data.error) setUploadMsg('❌ ' + data.error);
      else { setUploadMsg('✅ ' + (data.tasks || []).length + ' aksiyon!'); onRefresh(); }
    } catch { setUploadMsg('❌ Hata'); }
    setTimeout(() => setUploadMsg(''), 4000);
  };

  const startRecording = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const recorder = new MediaRecorder(stream, { mimeType: 'audio/webm' });
      const chunks = [];
      recorder.ondataavailable = e => { if (e.data.size > 0) chunks.push(e.data); };
      recorder.onstop = async () => {
        stream.getTracks().forEach(t => t.stop());
        const blob = new Blob(chunks, { type: 'audio/webm' });
        const file = new File([blob], `kayit_${Date.now()}.webm`, { type: 'audio/webm' });
        await handleUpload(file);
      };
      recorder.start(100);
      setMediaRecorder(recorder);
      setRecording(true);
      setUploadMsg('🔴 Kayıt yapılıyor...');
    } catch { setUploadMsg('❌ Mikrofon erişimi reddedildi'); }
  };

  const stopRecording = () => {
    if (mediaRecorder && mediaRecorder.state !== 'inactive') mediaRecorder.stop();
    setRecording(false);
  };

  const lastRecordRef = useRef(null);
  if (selectedRecord) lastRecordRef.current = selectedRecord;
  const panelRecord = selectedRecord || lastRecordRef.current;

  return (
    <div className="flex h-full">
      <div className="flex-1 overflow-y-auto">
        <div className="px-10 py-8">
          {/* Header */}
          <div className="flex items-start justify-between mb-8 fade-in-up">
            <div className="mb-8">
              <div className="flex items-end gap-4">
                <div>
                  <p style={{
                    fontSize: '11px',
                    fontWeight: '600',
                    letterSpacing: '3px',
                    textTransform: 'uppercase',
                    color: '#6366f1',
                    marginBottom: '4px',
                  }}>
                    İyi Günler
                  </p>
                  <h1 style={{
                    fontSize: '3rem',
                    fontWeight: '900',
                    background: 'linear-gradient(135deg, #ffffff 0%, #c7d2fe 60%, #818cf8 100%)',
                    WebkitBackgroundClip: 'text',
                    WebkitTextFillColor: 'transparent',
                    backgroundClip: 'text',
                    letterSpacing: '-2px',
                    lineHeight: 1,
                    fontFamily: "'Plus Jakarta Sans', 'Inter', sans-serif",
                  }}>
                    {userName}
                  </h1>
                </div>
                <motion.div
                  className="relative flex items-center justify-center text-purple-400 mb-1"
                  animate={{ y: [0, -6, 0] }}
                  transition={{ repeat: Infinity, duration: 2, ease: "easeInOut" }}
                >
                  <Mic size={28} />
                  <motion.span
                    className="absolute text-pink-400 font-bold pointer-events-none"
                    style={{ fontSize: '16px', top: '-10px', right: '-12px' }}
                    animate={{ opacity: [0, 1, 0], x: [0, 14], y: [0, -18], scale: [0.5, 1.2, 0.5] }}
                    transition={{ repeat: Infinity, duration: 2.5, delay: 0 }}
                  >♪</motion.span>
                  <motion.span
                    className="absolute text-blue-400 font-bold pointer-events-none"
                    style={{ fontSize: '13px', top: '4px', right: '-18px' }}
                    animate={{ opacity: [0, 1, 0], x: [0, 22], y: [0, -10], scale: [0.5, 1, 0.5] }}
                    transition={{ repeat: Infinity, duration: 2.5, delay: 1.2 }}
                  >♫</motion.span>
                </motion.div>
              </div>
            </div>
            <button onClick={onRefresh}
              className="flex items-center gap-2 px-4 py-2 bg-slate-800 hover:bg-slate-700 border border-slate-700 rounded-xl text-slate-300 text-sm font-semibold transition">
              <RefreshCw size={14} /> Yenile
            </button>
          </div>

          {/* Stats */}
          <div className="grid grid-cols-3 gap-4 mb-8 fade-in-up">
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.4, delay: 0 }}
              whileHover={{ scale: 1.02, transition: { duration: 0.2 } }}
              className="backdrop-blur-sm bg-slate-900/60 border border-slate-700/50 rounded-2xl p-6 hover:border-blue-500/30 transition-all duration-300"
            >
              <Mic size={24} className="text-blue-400 mb-3" />
              <div className="text-4xl font-extrabold text-white">{loading ? '...' : records.length}</div>
              <div className="text-slate-400 text-sm mt-2">Toplam Kayıt</div>
            </motion.div>
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.4, delay: 0.1 }}
              whileHover={{ scale: 1.02, transition: { duration: 0.2 } }}
              className="backdrop-blur-sm bg-slate-900/60 border border-slate-700/50 rounded-2xl p-6 hover:border-blue-500/30 transition-all duration-300"
            >
              <Zap size={24} className="text-orange-400 mb-3" />
              <div className="text-4xl font-extrabold text-white">{loading ? '...' : pending.length}</div>
              <div className="text-slate-400 text-sm mt-2">Bekleyen Aksiyon</div>
            </motion.div>
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.4, delay: 0.2 }}
              whileHover={{ scale: 1.02, transition: { duration: 0.2 } }}
              className="backdrop-blur-sm bg-slate-900/60 border border-slate-700/50 rounded-2xl p-6 hover:border-blue-500/30 transition-all duration-300"
            >
              <CheckCircle size={24} className="text-green-400 mb-3" />
              <div className="text-4xl font-extrabold text-white">{loading ? '...' : done.length}</div>
              <div className="text-slate-400 text-sm mt-2">Tamamlanan</div>
            </motion.div>
          </div>

          {/* Acil Aksiyonlar */}
          {urgent.length > 0 && (
            <div className="bg-gradient-to-r from-red-950/50 to-orange-950/50 border border-red-500/30 rounded-2xl p-5 mb-8">
              <div className="flex items-center justify-between mb-4">
                <h2 className="font-bold text-white flex items-center gap-2 text-lg">
                  <Flame size={16} className="text-red-400" /> Acil Aksiyonlar
                  <span className="bg-red-500 text-white text-xs px-2 py-0.5 rounded-full font-bold">{urgent.length}</span>
                </h2>
                <button onClick={() => onNavigate('tasks')} className="text-sm text-red-400 hover:text-red-300 font-semibold transition">Tümünü Gör →</button>
              </div>
              <div className="space-y-2">
                {urgent.slice(0, 3).map(t => {
                  const isPast = t.due_date && new Date(t.due_date) < new Date();
                  const daysLeft = t.due_date
                    ? Math.ceil((new Date(t.due_date) - new Date()) / (1000 * 60 * 60 * 24))
                    : null;

                  return (
                    <div key={t.id} className="flex items-center gap-3 bg-white/5 hover:bg-white/10 rounded-xl px-4 py-3 transition">
                      {isPast
                        ? <AlertTriangle size={14} className="text-red-400 flex-shrink-0" />
                        : <Flame size={14} className="text-orange-400 flex-shrink-0" />
                      }
                      <span className="text-sm text-white font-medium flex-1 truncate">{t.title}</span>
                      <div className="flex items-center gap-2 flex-shrink-0">
                        {t.due_date && (
                          <span className={`flex items-center gap-1 text-xs font-bold px-2 py-0.5 rounded-full ${
                            isPast
                              ? 'bg-red-500/20 text-red-300'
                              : daysLeft === 0
                              ? 'bg-orange-500/20 text-orange-300'
                              : 'bg-yellow-500/20 text-yellow-300'
                          }`}>
                            {isPast
                              ? <><AlertTriangle size={10} /> Geçti</>
                              : daysLeft === 0
                              ? <><Flame size={10} /> Bugün</>
                              : daysLeft === 1
                              ? <><Clock size={10} /> Yarın</>
                              : <><CalendarClock size={10} /> {daysLeft} gün</>
                            }
                          </span>
                        )}
                        <span className="text-xs text-slate-500">
                          {t.due_date ? new Date(t.due_date).toLocaleDateString('tr-TR') : ''}
                        </span>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          {/* Upload */}
          <div className="relative border-2 border-dashed border-slate-700 hover:border-blue-500 rounded-2xl p-8 mb-8 transition-all duration-300 cursor-pointer overflow-hidden group"
            onClick={() => fileRef.current?.click()}
            onDragOver={e => e.preventDefault()}
            onDrop={e => { e.preventDefault(); handleUpload(e.dataTransfer.files[0]); }}>
            <div className="absolute inset-0 bg-gradient-to-r from-blue-600/0 via-blue-600/5 to-indigo-600/0 opacity-0 group-hover:opacity-100 transition-opacity duration-500 pointer-events-none" />
            <input ref={fileRef} type="file" accept="audio/*,video/*" className="hidden" onChange={e => handleUpload(e.target.files[0])} />
            <div className="text-center">
              <Mic size={48} className="text-slate-600 mb-3 mx-auto" />
              <p className="text-white font-bold text-lg">Ses veya Video Yükle</p>
              <p className="text-slate-500 text-sm mt-1">Sürükle bırak veya tıkla · AI otomatik analiz eder</p>
              <div className="flex gap-2 justify-center mb-4 flex-wrap" onClick={e => e.stopPropagation()}>
                {['Eğitim', 'Toplantı', 'Röportaj', 'Diğer'].map(cat => (
                  <button
                    key={cat}
                    onClick={e => { e.stopPropagation(); setUploadCategory(cat); }}
                    className={`px-3 py-1.5 rounded-xl text-xs font-semibold transition ${
                      uploadCategory === cat
                        ? 'bg-blue-600 text-white'
                        : 'bg-slate-800 text-slate-400 hover:bg-slate-700 border border-slate-700'
                    }`}
                  >
                    {cat}
                  </button>
                ))}
              </div>
              <div className="flex items-center justify-center gap-3 mt-5">
                <button onClick={e => { e.stopPropagation(); fileRef.current?.click(); }}
                  className="flex items-center gap-1.5 px-5 py-2.5 bg-slate-800 hover:bg-slate-700 border border-slate-600 rounded-xl text-white text-sm font-semibold transition">
                  <Upload size={16} /> Dosya Seç
                </button>
                <button onClick={e => { e.stopPropagation(); recording ? stopRecording() : startRecording(); }}
                  className={`flex items-center gap-1.5 px-5 py-2.5 rounded-xl text-white text-sm font-semibold transition ${recording ? 'bg-red-600 hover:bg-red-700 animate-pulse recording-pulse' : 'bg-gradient-to-r from-blue-600 to-indigo-600 hover:from-blue-500 hover:to-indigo-500'}`}>
                  {recording ? '⏹ Durdur' : <><Mic size={16} /> Mikrofon</>}
                </button>
              </div>
              {uploadMsg && <p className="mt-4 text-sm font-bold text-blue-400">{uploadMsg}</p>}
            </div>
          </div>

          {/* Kategoriler */}
          <div className="mb-8">
            <h2 className="text-lg font-bold text-white mb-4 flex items-center gap-2">
              <FolderOpen size={18} className="text-slate-400" /> Kategoriler
            </h2>
            <div className="grid grid-cols-5 gap-3">
              {categories.map(cat => {
                const count = cat === 'Tümü' ? records.length : records.filter(r => r.category === cat).length;
                const colors = categoryColors[cat] || categoryColors['Diğer'];
                return (
                  <button key={cat} onClick={() => setActiveCategory(cat)}
                    className={`bg-gradient-to-br ${colors} border rounded-2xl p-4 text-left transition hover:scale-105 ${activeCategory === cat ? 'ring-2 ring-white/20' : ''}`}>
                    <div className="font-bold text-white text-sm">{cat}</div>
                    <div className="text-xs mt-1 opacity-70">{count} kayıt</div>
                  </button>
                );
              })}
            </div>
          </div>

          {/* Son Kayıtlar */}
          <div className="fade-in-up">
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-lg font-bold text-white flex items-center gap-2">
                <Mic size={18} className="text-slate-400" /> Son Kayıtlar
              </h2>
              <button onClick={() => onNavigate('records')} className="text-sm text-blue-400 hover:text-blue-300 font-semibold transition">Tümünü Gör →</button>
            </div>
            {filteredRecords.length === 0 ? (
              <div className="text-center py-12 text-slate-600">
                <Mic size={40} className="text-slate-600 mb-3 mx-auto" />
                <p className="font-semibold">Henüz kayıt yok</p>
              </div>
            ) : (
              <div className="space-y-3">
                {filteredRecords.slice(0, 5).map((r, index) => (
                  <motion.div
                    key={r.id}
                    initial={{ opacity: 0, x: -20 }}
                    animate={{ opacity: 1, x: 0 }}
                    transition={{ duration: 0.3, delay: index * 0.05 }}
                    whileHover={{ x: 4 }}
                    onClick={() => setSelectedRecord(selectedRecord?.id === r.id ? null : r)}
                    className={`card-3d flex items-center gap-4 p-4 rounded-2xl border cursor-pointer transition-all ${selectedRecord?.id === r.id ? 'bg-blue-600/10 border-blue-500/30' : 'bg-slate-900 border-slate-800 hover:border-slate-600 hover:bg-slate-800/50'}`}>
                    <div className="w-12 h-12 rounded-xl bg-blue-500/20 flex items-center justify-center flex-shrink-0">
                      <Mic size={20} className="text-blue-400" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="font-bold text-white truncate">{r.auto_title || r.file_name}</p>
                      <p className="text-slate-500 text-xs mt-0.5">{r.category} · {r.created_at ? new Date(r.created_at).toLocaleDateString('tr-TR') : ''}</p>
                      {r.transcript && <p className="text-slate-600 text-xs mt-1 truncate">{r.transcript.slice(0, 80)}...</p>}
                    </div>
                    <span className={`text-xs px-3 py-1 rounded-full font-bold flex-shrink-0 ${r.transcript ? 'bg-green-500/10 text-green-400 border border-green-500/20' : 'bg-slate-700 text-slate-400'}`}>
                      {r.transcript ? '✓ Transkript' : 'Bekliyor'}
                    </span>
                  </motion.div>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Overlay */}
      <div
        className={`fixed inset-0 bg-black/40 backdrop-blur-sm z-40 transition-opacity duration-300 ${selectedRecord ? 'opacity-100 pointer-events-auto' : 'opacity-0 pointer-events-none'}`}
        onClick={() => setSelectedRecord(null)}
      />

      {/* Detay Paneli — slide-in */}
      <div className={`fixed right-0 top-0 h-full w-[440px] bg-slate-900 border-l border-slate-700 z-50 shadow-2xl flex flex-col transition-transform duration-300 ease-out ${selectedRecord ? 'translate-x-0' : 'translate-x-full'}`}>
        {panelRecord && (
          <div className="flex-1 overflow-y-auto p-6">
            <div className="flex items-start justify-between mb-6">
              <div className="flex items-center gap-3">
                <div className="w-12 h-12 rounded-xl overflow-hidden flex-shrink-0">
                  <img src="/logo.png" alt="logo" className="w-full h-full object-cover" />
                </div>
                <div>
                  <h3 className="font-bold text-white text-lg">{panelRecord.auto_title || panelRecord.file_name}</h3>
                  <p className="text-slate-400 text-sm">{panelRecord.category} · {panelRecord.created_at ? new Date(panelRecord.created_at).toLocaleDateString('tr-TR') : ''}</p>
                </div>
              </div>
              <button onClick={() => setSelectedRecord(null)}
                className="w-9 h-9 rounded-xl bg-slate-800 hover:bg-slate-700 flex items-center justify-center text-slate-400 hover:text-white transition text-lg flex-shrink-0">✕</button>
            </div>

            {audioUrl && (
              <div className="bg-slate-800 border border-slate-700 rounded-2xl p-4 mb-4">
                <p className="text-xs font-semibold text-slate-400 uppercase tracking-wider mb-3">🎙️ Ses Kaydı</p>
                <audio
                  ref={audioRef}
                  src={audioUrl}
                  controls
                  className="w-full"
                  style={{ filter: 'invert(1) hue-rotate(180deg)', height: '36px' }}
                  onPlay={() => setPlaying(true)}
                  onPause={() => setPlaying(false)}
                />
              </div>
            )}

            <div className="bg-slate-950 rounded-2xl p-4 border border-slate-800">
              <p className="text-xs font-bold text-slate-400 uppercase tracking-wider mb-3">📄 Transkript</p>
              <p className="text-sm text-slate-300 leading-relaxed">
                {panelRecord.transcript || 'Transkript henüz hazır değil.'}
              </p>
            </div>

            <div className="mt-4">
              <p className="text-xs font-bold text-slate-400 uppercase tracking-wider mb-3">⚡ Aksiyonlar</p>
              <div className="space-y-2">
                {tasks.filter(t => t.record_id === panelRecord.id).map(t => (
                  <div key={t.id} className={`flex items-center gap-3 p-3 rounded-xl border ${t.status === 'done' ? 'bg-slate-800/50 border-slate-700 opacity-60' : 'bg-slate-800 border-slate-700'}`}>
                    <span className={t.status === 'done' ? 'text-green-400' : 'text-orange-400'}>{t.status === 'done' ? '✅' : '⚡'}</span>
                    <p className={`text-sm flex-1 ${t.status === 'done' ? 'line-through text-slate-500' : 'text-white'}`}>{t.title}</p>
                    {t.due_date && <span className="text-xs text-slate-500">{new Date(t.due_date).toLocaleDateString('tr-TR')}</span>}
                  </div>
                ))}
                {tasks.filter(t => t.record_id === panelRecord.id).length === 0 && (
                  <p className="text-slate-600 text-sm text-center py-4">Bu kayıt için aksiyon yok</p>
                )}
              </div>
            </div>

            <div className="mt-4">
              <p className="text-xs font-bold text-slate-400 uppercase tracking-wider mb-3">🗒️ Notlar</p>
              <div className="space-y-3">
                <textarea
                  value={noteText}
                  onChange={e => setNoteText(e.target.value)}
                  placeholder="Bu kayıt için notunuzu yazın..."
                  className="w-full h-36 bg-slate-950 border border-slate-800 rounded-xl p-4 text-slate-300 text-sm resize-none focus:outline-none focus:border-blue-500 placeholder-slate-600 transition"
                />
                <button
                  onClick={saveNote}
                  className={`w-full py-2.5 rounded-xl font-bold text-sm transition ${noteSaved ? 'bg-green-600 text-white' : 'bg-blue-600 hover:bg-blue-500 text-white'}`}
                >
                  {noteSaved ? '✅ Kaydedildi!' : '💾 Notu Kaydet'}
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
