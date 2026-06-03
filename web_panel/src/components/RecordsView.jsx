import { useState, useRef, useEffect } from 'react';
import { Mic, Trash2, Upload, Search, FileText, StickyNote, Zap, GraduationCap, Users, MessageSquare, Folder, Layers } from 'lucide-react';
import api from '../api';

const CATEGORIES = ['Eğitim', 'Toplantı', 'Röportaj', 'Diğer'];

const CATEGORY_BORDER = {
  'Eğitim':   'border-l-4 border-l-blue-500/60',
  'Toplantı': 'border-l-4 border-l-purple-500/60',
  'Röportaj': 'border-l-4 border-l-amber-500/60',
  'Diğer':    'border-l-4 border-l-slate-500/60',
};

export default function RecordsView({ records, onDelete, onUpload, tasks = [] }) {
  const [activeCategory, setActiveCategory] = useState('Tümü');
  const [uploading, setUploading] = useState(false);
  const [uploadMsg, setUploadMsg] = useState('');
  const [selectedCategory, setSelectedCategory] = useState('Eğitim');
  const [selectedRecord, setSelectedRecord] = useState(null);
  const [detailTab, setDetailTab] = useState('transcript');
  const [searchQuery, setSearchQuery] = useState('');
  const [noteText, setNoteText] = useState('');
  const [noteSaved, setNoteSaved] = useState(false);
  const fileRef = useRef();
  const [recording, setRecording] = useState(false);
  const [mediaRecorder, setMediaRecorder] = useState(null);
  const [audioChunks, setAudioChunks] = useState([]);
  const [audioBlobUrl, setAudioBlobUrl] = useState(null);
  const [audioLoading, setAudioLoading] = useState(false);
  const audioRef = useRef();

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
    if (!selectedRecord) return;
    setAudioBlobUrl(null);
    setAudioLoading(true);

    const tok = localStorage.getItem('token');
    fetch(`http://localhost:8000/api/records/${selectedRecord.id}/audio?token=${tok}`, {
      headers: { 'Authorization': `Bearer ${tok}` }
    })
      .then(res => {
        if (!res.ok) throw new Error('Ses yüklenemedi');
        return res.blob();
      })
      .then(blob => {
        const url = URL.createObjectURL(blob);
        setAudioBlobUrl(url);
      })
      .catch(err => console.error('[Audio]', err))
      .finally(() => setAudioLoading(false));
  }, [selectedRecord]);

  const handleUpload = async (file) => {
    if (!file) return;
    setUploading(true);
    setUploadMsg('Analiz ediliyor...');
    try {
      const data = await api.uploadAudio(file, selectedCategory);
      if (data.error) {
        setUploadMsg('❌ ' + data.error);
      } else {
        setUploadMsg(`✅ Tamamlandı! ${(data.tasks || []).length} aksiyon tespit edildi.`);
        onUpload();
      }
    } catch {
      setUploadMsg('❌ Yükleme başarısız');
    }
    setUploading(false);
    setTimeout(() => setUploadMsg(''), 3000);
  };

  const handleDelete = async (id) => {
    await api.deleteRecord(id);
    onDelete();
    setSelectedRecord(null);
  };

  const openRecord = (r) => {
    setSelectedRecord(r);
    setSearchQuery('');
    setDetailTab('transcript');
  };

  const startRecording = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const recorder = new MediaRecorder(stream, { mimeType: 'audio/webm' });
      const chunks = [];

      recorder.ondataavailable = (e) => {
        if (e.data.size > 0) chunks.push(e.data);
      };

      recorder.onstop = async () => {
        stream.getTracks().forEach(t => t.stop());
        const blob = new Blob(chunks, { type: 'audio/webm' });
        if (blob.size < 1000) {
          setUploadMsg('❌ Kayıt çok kısa, tekrar deneyin');
          return;
        }
        const file = new File([blob], `kayit_${Date.now()}.webm`, { type: 'audio/webm' });
        await handleUpload(file);
      };

      recorder.start(100);
      setMediaRecorder(recorder);
      setRecording(true);
      setUploadMsg('🔴 Kayıt yapılıyor...');
    } catch (e) {
      setUploadMsg('❌ Mikrofon erişimi reddedildi');
    }
  };

  const stopRecording = () => {
    if (mediaRecorder && mediaRecorder.state !== 'inactive') {
      mediaRecorder.stop();
    }
    setRecording(false);
    setUploadMsg('⏳ İşleniyor...');
  };

  const lastRecordRef = useRef(null);
  if (selectedRecord) lastRecordRef.current = selectedRecord;
  const panelRecord = selectedRecord || lastRecordRef.current;

  const recordTasks = panelRecord
    ? tasks.filter(t => String(t.record_id) === String(panelRecord.id))
    : [];

  const TABS = [
    { key: 'transcript', label: 'Transkript', icon: <FileText size={14} /> },
    { key: 'notes',      label: 'Notlar',     icon: <StickyNote size={14} /> },
    { key: 'actions',    label: 'Aksiyonlar', icon: <Zap size={14} /> },
  ];

  return (
    <div className="p-8 max-w-5xl mx-auto">
      <h1 className="text-3xl font-extrabold text-white flex items-center gap-2">
        <Upload size={28} className="text-slate-400" /> Ses Kayıtları
      </h1>
      <p className="text-slate-400 text-sm mt-1 mb-4">{records.length} kayıt · Kayda tıklayarak detayları görüntüle</p>

      <div className="flex flex-wrap gap-2 mb-6">
        {['Tümü', 'Eğitim', 'Toplantı', 'Röportaj', 'Diğer'].map(cat => {
          const count = cat === 'Tümü'
            ? records.length
            : records.filter(r => r.category === cat).length;
          const icons = {
            'Tümü': <Layers size={14} />,
            'Eğitim': <GraduationCap size={14} />,
            'Toplantı': <Users size={14} />,
            'Röportaj': <MessageSquare size={14} />,
            'Diğer': <Folder size={14} />,
          };
          return (
            <button
              key={cat}
              onClick={() => setActiveCategory(cat)}
              className={`flex items-center gap-2 px-4 py-2 rounded-xl font-semibold text-sm transition ${
                activeCategory === cat
                  ? 'bg-blue-600 text-white'
                  : 'bg-slate-800/50 text-slate-400 hover:bg-slate-700 hover:text-white border border-slate-700'
              }`}
            >
              {icons[cat]}
              {cat}
              <span className="text-xs opacity-70">({count})</span>
            </button>
          );
        })}
      </div>

      {/* Upload */}
      <div
        className="glass border-2 border-dashed border-slate-700 hover:border-blue-500 rounded-2xl p-8 text-center mb-8 transition cursor-pointer"
        onClick={() => fileRef.current?.click()}
        onDragOver={e => e.preventDefault()}
        onDrop={e => { e.preventDefault(); handleUpload(e.dataTransfer.files[0]); }}
      >
        <input ref={fileRef} type="file" accept="audio/*,video/*" className="hidden" onChange={e => handleUpload(e.target.files[0])} />
        <Mic size={40} className="text-slate-600 mb-3 mx-auto" />
        <p className="text-white font-semibold">Ses veya video dosyası yükle</p>
        <p className="text-slate-500 text-sm mt-1">Sürükle bırak veya tıkla</p>
        <div className="flex items-center justify-center gap-2 mt-4 flex-wrap">
          {CATEGORIES.map(c => (
            <button
              key={c}
              onClick={e => { e.stopPropagation(); setSelectedCategory(c); }}
              className={`px-3 py-1 rounded-full text-xs font-semibold transition ${selectedCategory === c ? 'bg-blue-600 text-white' : 'bg-slate-800 text-slate-400 hover:bg-slate-700'}`}
            >
              {c}
            </button>
          ))}
        </div>
        {uploading && <div className="mt-4 text-blue-400 text-sm animate-pulse">⏳ {uploadMsg}</div>}
        {!uploading && uploadMsg && <div className="mt-4 text-sm font-semibold">{uploadMsg}</div>}
      </div>

      <div className="flex items-center justify-center mt-4">
        <button
          onClick={recording ? stopRecording : startRecording}
          className={`flex items-center gap-3 px-6 py-3 rounded-2xl font-bold text-white transition ${
            recording
              ? 'bg-red-600 hover:bg-red-700 animate-pulse'
              : 'bg-gradient-to-r from-blue-600 to-indigo-600 hover:shadow-lg hover:shadow-blue-500/30'
          }`}
        >
          {recording ? '⏹ Kaydı Durdur' : <><Mic size={20} /> Mikrofon ile Kaydet</>}
        </button>
      </div>
      {recording && (
        <p className="text-center text-red-400 text-sm mt-2 animate-pulse">
          ● Kayıt yapılıyor...
        </p>
      )}

      {/* Records List */}
      <div className="grid gap-4 mt-8">
        {(activeCategory === 'Tümü' ? records : records.filter(r => r.category === activeCategory)).map(r => (
          <div
            key={r.id}
            className={`card-3d bg-slate-900 border border-slate-800 rounded-2xl p-5 hover:border-slate-600 transition cursor-pointer group ${CATEGORY_BORDER[r.category] || ''}`}
            onClick={() => openRecord(r)}
          >
            <div className="flex items-start gap-4">
              <div className="w-12 h-12 rounded-xl bg-blue-500/20 flex items-center justify-center flex-shrink-0">
                <Mic size={20} className="text-blue-400" />
              </div>
              <div className="flex-1 min-w-0">
                <p className="font-semibold text-white">{r.auto_title || r.file_name}</p>
                <p className="text-slate-500 text-sm mt-0.5">{r.category} · {r.created_at ? new Date(r.created_at).toLocaleDateString('tr-TR') : ''}</p>
                {r.transcript && <p className="text-slate-400 text-xs mt-2 line-clamp-2">{r.transcript.slice(0, 120)}...</p>}
              </div>
              <div className="flex items-center gap-2 flex-shrink-0">
                <button
                  onClick={e => { e.stopPropagation(); handleDelete(r.id); }}
                  className="w-9 h-9 rounded-xl bg-slate-800 hover:bg-red-900/30 text-slate-500 hover:text-red-400 flex items-center justify-center transition"
                >
                  <Trash2 size={14} />
                </button>
                <span className="text-slate-600 group-hover:text-slate-300 transition text-lg leading-none">›</span>
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* Slide-in Detail Panel */}
      <div
        className={`fixed inset-0 bg-black/40 z-40 transition-opacity duration-300 ${selectedRecord ? 'opacity-100 pointer-events-auto' : 'opacity-0 pointer-events-none'}`}
        onClick={() => setSelectedRecord(null)}
      />
      <div className={`fixed right-0 top-0 h-full w-[440px] bg-slate-950 border-l border-slate-700 z-50 shadow-2xl flex flex-col transition-transform duration-300 ease-out ${selectedRecord ? 'translate-x-0' : 'translate-x-full'}`}>
        {panelRecord && (
          <>
            {/* Panel Header */}
            <div className="p-6 border-b border-slate-800 flex-shrink-0">
              <div className="flex items-start justify-between mb-5">
                <div className="flex items-center gap-3 flex-1 min-w-0 mr-3">
                  <div className="w-12 h-12 rounded-xl bg-blue-500/20 flex items-center justify-center flex-shrink-0">
                    <Mic size={20} className="text-blue-400" />
                  </div>
                  <div className="min-w-0">
                    <h2 className="font-extrabold text-white leading-tight truncate">{panelRecord.auto_title || panelRecord.file_name}</h2>
                    <p className="text-slate-400 text-xs mt-0.5">
                      {panelRecord.category} · {panelRecord.created_at ? new Date(panelRecord.created_at).toLocaleDateString('tr-TR') : ''}
                    </p>
                  </div>
                </div>
                <button
                  onClick={() => setSelectedRecord(null)}
                  className="w-8 h-8 rounded-xl bg-slate-800 hover:bg-slate-700 flex items-center justify-center text-slate-400 hover:text-white transition flex-shrink-0"
                >✕</button>
              </div>
              <div className="flex items-center gap-2 flex-wrap">
                {TABS.map(tab => (
                  <button
                    key={tab.key}
                    onClick={() => setDetailTab(tab.key)}
                    className={`flex items-center gap-1.5 px-4 py-2 rounded-xl text-xs font-semibold transition ${detailTab === tab.key ? 'bg-blue-600 text-white shadow-lg shadow-blue-600/20' : 'bg-slate-800 text-slate-400 hover:bg-slate-700 hover:text-white'}`}
                  >
                    {tab.icon} {tab.label}
                  </button>
                ))}
                <button
                  onClick={() => handleDelete(panelRecord.id)}
                  className="ml-auto flex items-center gap-1 px-3 py-1.5 rounded-lg text-xs font-semibold bg-red-900/30 text-red-400 hover:bg-red-900/50 transition"
                >
                  <Trash2 size={12} /> Sil
                </button>
              </div>
            </div>

            {/* Panel Content */}
            <div className="flex-1 overflow-y-auto p-6">
              {(audioLoading || audioBlobUrl) && (
                <div className="bg-slate-800 border border-slate-700 rounded-2xl p-4 mb-4">
                  <p className="text-xs font-semibold text-slate-400 uppercase tracking-wider mb-3 flex items-center gap-1.5">
                    <Mic size={14} /> Ses Kaydı
                  </p>
                  {audioLoading && (
                    <p className="text-xs text-slate-400 animate-pulse">🎵 Ses yükleniyor...</p>
                  )}
                  {audioBlobUrl && (
                    <audio
                      ref={audioRef}
                      src={audioBlobUrl}
                      controls
                      className="w-full"
                      style={{ height: '36px' }}
                    />
                  )}
                </div>
              )}
              {detailTab === 'transcript' && (
                <>
                  <input
                    value={searchQuery}
                    onChange={e => setSearchQuery(e.target.value)}
                    placeholder="Transkriptte ara... (Ctrl+F)"
                    className="w-full px-3 py-2.5 bg-slate-800 border border-slate-700 rounded-xl text-sm text-white placeholder-slate-500 focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500/20 mb-4 transition"
                  />
                  {panelRecord.transcript ? (
                    <p className="text-sm text-slate-300 leading-relaxed">
                      {searchQuery
                        ? panelRecord.transcript
                            .split(new RegExp(`(${searchQuery.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')})`, 'gi'))
                            .map((part, idx) =>
                              part.toLowerCase() === searchQuery.toLowerCase()
                                ? <mark key={idx} className="bg-yellow-500/30 text-yellow-300 rounded px-0.5">{part}</mark>
                                : part
                            )
                        : panelRecord.transcript}
                    </p>
                  ) : (
                    <p className="text-slate-500 text-sm text-center py-8">Transkript mevcut değil</p>
                  )}
                </>
              )}

              {detailTab === 'notes' && (
                <div className="space-y-3">
                  <textarea
                    value={noteText}
                    onChange={e => setNoteText(e.target.value)}
                    placeholder="Bu kayıt için notunuzu yazın..."
                    className="w-full h-48 bg-slate-900 border border-slate-700 rounded-xl p-4 text-slate-300 text-sm resize-none focus:outline-none focus:border-blue-500 placeholder-slate-600 transition"
                  />
                  <button
                    onClick={saveNote}
                    className={`w-full py-2.5 rounded-xl font-bold text-sm transition ${noteSaved ? 'bg-green-600 text-white' : 'bg-blue-600 hover:bg-blue-500 text-white'}`}
                  >
                    {noteSaved ? '✅ Kaydedildi!' : '💾 Notu Kaydet'}
                  </button>
                </div>
              )}

              {detailTab === 'actions' && (
                <div className="space-y-2">
                  {recordTasks.length === 0 ? (
                    <div className="text-center py-8">
                      <Zap size={32} className="text-slate-600 mb-2 mx-auto" />
                      <p className="text-slate-500 text-sm">Bu kayıtta aksiyon yok</p>
                    </div>
                  ) : (
                    recordTasks.map(t => (
                      <div key={t.id} className={`flex items-center gap-3 p-3 rounded-xl border ${t.status === 'done' ? 'bg-slate-800/50 border-slate-700 opacity-60' : 'bg-slate-800 border-slate-700'}`}>
                        <span className={t.status === 'done' ? 'text-green-400' : 'text-orange-400'}>{t.status === 'done' ? '✅' : '○'}</span>
                        <p className={`text-sm flex-1 ${t.status === 'done' ? 'line-through text-slate-500' : 'text-white'}`}>{t.title}</p>
                        {t.due_date && <span className="text-xs text-slate-500">{new Date(t.due_date).toLocaleDateString('tr-TR')}</span>}
                      </div>
                    ))
                  )}
                </div>
              )}
            </div>
          </>
        )}
      </div>
    </div>
  );
}
