import { useState } from 'react';
import { Home, Zap, Folder, Calendar, BarChart3, LogOut, Trophy, ChevronUp } from 'lucide-react';
import { motion } from 'framer-motion';

const NAV = [
  { id: 'home',       icon: <Home size={18} />,      label: 'Ana Sayfa' },
  { id: 'tasks',      icon: <Zap size={18} />,       label: 'Aksiyonlar' },
  { id: 'records',    icon: <Folder size={18} />,    label: 'Kayıtlar' },
  { id: 'calendar',   icon: <Calendar size={18} />,  label: 'Aksiyon Takvimi' },
  { id: 'stats',      icon: <Trophy size={20} />,   label: 'İstatistikler & Başarımlar' },
];

export default function Sidebar({ activeTab, onNavigate, userName, onLogout }) {
  const [showProfile, setShowProfile] = useState(false);
  const initials = userName.trim().split(' ').map(p => p[0]).join('').toUpperCase().slice(0, 2);

  return (
    <aside className="w-72 glass border-r border-slate-800/50 flex flex-col h-full">
      {/* Logo */}
      <div className="flex items-center gap-3 px-5 py-5 border-b border-slate-800/50">
        <motion.div
          animate={{ y: [-4, 4, -4] }}
          transition={{ repeat: Infinity, duration: 4, ease: "easeInOut" }}
          className="flex-shrink-0 w-12 h-12 rounded-xl overflow-hidden shadow-lg shadow-indigo-500/30"
          style={{minWidth:'48px', minHeight:'48px'}}
        >
          <img src="/logo.png" alt="logo" style={{width:'100%', height:'100%', objectFit:'cover', display:'block'}} />
        </motion.div>
        <h1 className="text-2xl font-black text-transparent bg-clip-text bg-gradient-to-r from-blue-400 via-indigo-400 to-purple-400" style={{filter:'drop-shadow(0 0 12px rgba(129,140,248,0.6))'}}>
          VoiceToAction
        </h1>
      </div>

      {/* Nav */}
      <nav className="flex-1 p-4 space-y-1">
        {NAV.map(item => (
          <motion.button
            key={item.id}
            whileHover={{ x: 4 }}
            whileTap={{ scale: 0.98 }}
            transition={{ duration: 0.15 }}
            onClick={() => onNavigate(item.id)}
            className={`w-full flex items-center gap-3.5 px-4 py-3.5 rounded-xl text-sm font-semibold transition-all ${
              activeTab === item.id
                ? 'bg-blue-600 text-white shadow-lg shadow-blue-600/20'
                : 'text-slate-400 hover:bg-slate-800 hover:text-white'
            }`}
          >
            <span className="flex-shrink-0">{item.icon}</span>
            {item.label}
          </motion.button>
        ))}
      </nav>

      {/* User */}
      <div className="p-4 border-t border-slate-800/50">
        <button
          onClick={() => setShowProfile(!showProfile)}
          className="w-full flex items-center gap-3 p-3 rounded-xl hover:bg-slate-800/50 transition group"
        >
          <div className="w-9 h-9 rounded-full bg-gradient-to-br from-blue-600 to-indigo-600 flex items-center justify-center text-sm font-bold text-white flex-shrink-0">
            {initials}
          </div>
          <div className="flex-1 min-w-0 text-left">
            <p className="text-sm font-semibold text-white truncate">{userName}</p>
            <p className="text-xs text-slate-500 truncate">{localStorage.getItem('userEmail') || 'Kullanıcı'}</p>
          </div>
          <ChevronUp size={14} className={`text-slate-500 transition-transform ${showProfile ? 'rotate-180' : ''}`} />
        </button>

        {showProfile && (
          <motion.div
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            className="mt-2 p-3 bg-slate-800/50 rounded-xl border border-slate-700/50 space-y-1"
          >
            <div className="px-2 py-1.5 mb-2 border-b border-slate-700/50">
              <p className="text-xs text-slate-500">Oturum açık</p>
              <p className="text-xs font-semibold text-slate-300 truncate">{localStorage.getItem('userEmail') || ''}</p>
            </div>
            <button
              onClick={onLogout}
              className="w-full flex items-center gap-2 px-3 py-2 rounded-lg hover:bg-red-900/30 text-slate-400 hover:text-red-400 text-sm font-semibold transition"
            >
              <LogOut size={14} />
              Çıkış Yap
            </button>
          </motion.div>
        )}
      </div>
    </aside>
  );
}
