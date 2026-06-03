import { useState, useRef, useEffect } from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import api from '../api';


const markdownComponents = {
  code({ node, inline, className, children, ...props }) {
    const match = /language-(\w+)/.exec(className || '');
    if (!inline && match && match[1] === 'mermaid') {
      return (
        <div className="my-3 bg-slate-950/50 rounded-xl p-3 border border-slate-700/50">
          <p className="text-xs text-purple-400 font-semibold mb-2">🕸️ Zihin Haritası</p>
          <pre className="text-xs text-slate-300 whitespace-pre-wrap overflow-x-auto">
            {String(children).replace(/\n$/, '')}
          </pre>
        </div>
      );
    }
    return (
      <code className="bg-slate-800 px-1.5 py-0.5 rounded text-xs text-blue-300 font-mono" {...props}>
        {children}
      </code>
    );
  },
  p({ children }) { return <p className="text-sm text-slate-300 leading-relaxed mb-1">{children}</p>; },
  strong({ children }) { return <strong className="font-bold text-white">{children}</strong>; },
  li({ children }) { return <li className="text-sm text-slate-300 ml-4 mb-0.5 list-disc">{children}</li>; },
  ul({ children }) { return <ul className="my-1">{children}</ul>; },
  ol({ children }) { return <ol className="my-1 list-decimal">{children}</ol>; },
  h1({ children }) { return <h1 className="text-base font-bold text-white mt-2 mb-1">{children}</h1>; },
  h2({ children }) { return <h2 className="text-sm font-bold text-white mt-2 mb-1">{children}</h2>; },
  h3({ children }) { return <h3 className="text-sm font-semibold text-slate-200 mt-1 mb-0.5">{children}</h3>; },
};

function getCmdInfo(cmd) {
  const c = cmd.split('|')[0];
  if (c === 'CMD_TASKS') return { label: '⚡ Aksiyonlarım', color: 'bg-blue-600/20 text-blue-400 border-blue-500/30' };
  if (c === 'CMD_RECORDS') return { label: '📁 Kayıtlarım', color: 'bg-purple-600/20 text-purple-400 border-purple-500/30' };
  if (c === 'CMD_MENU') return { label: '🏠 Ana Menü', color: 'bg-slate-700/50 text-slate-300 border-slate-600/30' };
  if (c.startsWith('CMD_SELECT_')) { const name = cmd.split('|')[1] || 'Kayıt Seç'; return { label: `🎙️ ${name}`, color: 'bg-indigo-600/20 text-indigo-400 border-indigo-500/30' }; }
  if (c.startsWith('CMD_SUMMARIZE_')) return { label: '📝 Özetle', color: 'bg-violet-600/20 text-violet-400 border-violet-500/30' };
  if (c.startsWith('CMD_CALENDAR_')) return { label: '📅 Takvim Planı', color: 'bg-cyan-600/20 text-cyan-400 border-cyan-500/30' };
  if (c.startsWith('CMD_MEETING_')) return { label: '📌 Ders Notu', color: 'bg-green-600/20 text-green-400 border-green-500/30' };
  if (c.startsWith('CMD_EXAM_')) return { label: '☕ Quiz Molası', color: 'bg-amber-600/20 text-amber-400 border-amber-500/30' };
  if (c.startsWith('CMD_CODE_EXTRACT_')) return { label: '💻 Kod Çıkarıcı', color: 'bg-cyan-600/20 text-cyan-400 border-cyan-500/30' };
  if (c.startsWith('CMD_CONCEPT_EXTRACT_')) return { label: '📚 Ders Notu & Kavramlar', color: 'bg-emerald-600/20 text-emerald-400 border-emerald-500/30' };
  if (c.startsWith('CMD_SAVE_NOTE_')) return { label: '💾 Notlara Kaydet', color: 'bg-orange-600/20 text-orange-400 border-orange-500/30' };
  if (c.startsWith('CMD_SIMPLIFY_')) return { label: '🧠 Mala Anlatır Gibi Anlat', color: 'bg-sky-600/20 text-sky-400 border-sky-500/30' };
  if (c.startsWith('CMD_RESOURCES_')) return { label: '🎬 Kaynak Öner', color: 'bg-orange-600/20 text-orange-400 border-orange-500/30' };
  if (c.startsWith('CMD_TECH_EXTRACT_')) return { label: '💻 Teknik Analiz', color: 'bg-cyan-600/20 text-cyan-400 border-cyan-500/30' };
  if (c.startsWith('CMD_TEAM_MATRIX_')) return { label: '👥 Ekip Matrisi', color: 'bg-blue-600/20 text-blue-400 border-blue-500/30' };
  if (c.startsWith('CMD_QANS_')) { const parts = c.split('_'); const choice = parts[3]; return { label: `${choice})`, color: 'bg-indigo-600/20 text-indigo-400 border-indigo-500/30' }; }
  const displayText = cmd.split('|')[1];
  if (displayText) return { label: displayText, color: 'bg-slate-700/50 text-slate-300 border-slate-600/30' };
  return { label: c, color: 'bg-slate-700/50 text-slate-300 border-slate-600/30' };
}

export default function ChatView() {
  const [messages, setMessages] = useState([{
    text: 'VoiceToAction Asistanına hoş geldiniz! 👋\n\nSes kayıtlarınızı analiz edebilir, özetleyebilir ve aksiyonlarınızı yönetebilirim.',
    isUser: false,
    options: ['CMD_TASKS', 'CMD_RECORDS']
  }]);
  const [input, setInput] = useState('');
  const [typing, setTyping] = useState(false);
  const bottomRef = useRef();

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  const sendMessage = async (text, displayText) => {
    if (!text.trim() || typing) return;
    setMessages(prev => [...prev, { text: displayText || text, isUser: true }]);
    setInput('');
    setTyping(true);
    try {
      const data = await api.sendChatMessage(text);
      setMessages(prev => [...prev, {
        text: data.answer || 'Yanıt alınamadı',
        isUser: false,
        options: data.options || []
      }]);
    } catch {
      setMessages(prev => [...prev, { text: 'Bağlantı hatası oluştu.', isUser: false, options: ['CMD_MENU'] }]);
    }
    setTyping(false);
  };

  return (
    <div className="flex flex-col h-full bg-slate-950">
      {/* Header */}
      <div className="flex items-center gap-3 px-5 py-3 border-b border-slate-800 bg-slate-900/80 backdrop-blur flex-shrink-0">
        <div className="w-9 h-9 rounded-xl overflow-hidden flex-shrink-0">
          <img src="/logo.png" alt="asistan" className="w-full h-full object-cover" />
        </div>
        <div>
          <p className="font-semibold text-white text-sm">VoiceToAction Asistanı</p>
          <p className="text-xs text-green-400 flex items-center gap-1">
            <span className="w-1.5 h-1.5 rounded-full bg-green-400 inline-block"></span>
            Çevrimiçi
          </p>
        </div>
      </div>

      {/* Mesajlar */}
      <div className="flex-1 overflow-y-auto px-5 py-4 space-y-4">
        {messages.map((msg, i) => (
          <div key={i} className={`flex ${msg.isUser ? 'justify-end' : 'justify-start'} gap-2`}>
            {!msg.isUser && (
              <div className="w-7 h-7 rounded-lg overflow-hidden flex-shrink-0 mt-1">
                <img src="/logo.png" alt="bot" className="w-full h-full object-cover" />
              </div>
            )}
            <div className="max-w-sm lg:max-w-lg">
              <div className={`px-4 py-3 rounded-2xl ${
                msg.isUser
                  ? 'bg-indigo-600 text-white rounded-tr-sm'
                  : 'bg-slate-800 border border-slate-700/50 border-l-2 border-l-indigo-500 rounded-tl-sm'
              }`}>
                {msg.isUser ? (
                  <p className="text-sm text-white">{msg.text}</p>
                ) : (
                  <ReactMarkdown remarkPlugins={[remarkGfm]} components={markdownComponents}>
                    {msg.text}
                  </ReactMarkdown>
                )}
              </div>
              {msg.options?.length > 0 && (
                <div className="flex flex-wrap gap-2 mt-2">
                  {msg.options.map((opt, j) => {
                    const info = getCmdInfo(opt);
                    return (
                      <button
                        key={j}
                        onClick={() => sendMessage(opt.split('|')[0], info.label)}
                        disabled={typing}
                        className={`flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-semibold border transition hover:opacity-80 disabled:opacity-40 ${info.color}`}
                      >
                        {info.label}
                      </button>
                    );
                  })}
                </div>
              )}
            </div>
          </div>
        ))}
        {typing && (
          <div className="flex gap-2">
            <div className="w-7 h-7 rounded-lg overflow-hidden flex-shrink-0">
              <img src="/logo.png" alt="bot" className="w-full h-full object-cover" />
            </div>
            <div className="bg-slate-800 border border-slate-700/50 border-l-2 border-l-indigo-500 px-4 py-3 rounded-2xl">
              <div className="flex gap-1">
                {[0,1,2].map(i => (
                  <div key={i} className="w-2 h-2 bg-indigo-400 rounded-full animate-bounce"
                    style={{animationDelay: `${i * 150}ms`}} />
                ))}
              </div>
            </div>
          </div>
        )}
        <div ref={bottomRef} />
      </div>

      {/* Input */}
      <div className="p-4 border-t border-slate-800 bg-slate-900 flex-shrink-0">
        <div className="flex gap-3">
          <input
            value={input}
            onChange={e => setInput(e.target.value)}
            onKeyDown={e => e.key === 'Enter' && sendMessage(input)}
            placeholder="Bir şey sor veya butona bas..."
            className="flex-1 px-4 py-3 bg-slate-800 border border-slate-700 rounded-xl text-white placeholder-slate-500 focus:outline-none focus:border-blue-500 text-sm transition"
          />
          <button
            onClick={() => sendMessage(input)}
            disabled={typing || !input.trim()}
            className="w-12 h-12 bg-gradient-to-br from-blue-500 to-indigo-600 rounded-xl flex items-center justify-center text-white transition disabled:opacity-50 hover:shadow-lg hover:shadow-blue-500/30"
          >
            ➤
          </button>
        </div>
      </div>
    </div>
  );
}
