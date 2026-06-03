import { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Trophy, Zap, Mic, Flame, Lock, Star, Target, Clock, BookOpen, Swords, Shield, Crown, CheckCircle2, Calendar, TrendingUp, Award, Moon, Timer, Sun, GraduationCap, Activity } from 'lucide-react';

// GÜNLÜK GÖREVLER
const getDailyQuests = (records, tasks) => {
  const today = new Date().toISOString().split('T')[0];
  const todayTasks = tasks.filter(t => t.due_date && t.due_date.substring(0,10) === today);
  const todayDone = todayTasks.filter(t => t.status === 'done');
  const todayRecords = records.filter(r => r.created_at && r.created_at.substring(0,10) === today);
  const totalDone = tasks.filter(t => t.status === 'done').length;
  const pending = tasks.filter(t => t.status !== 'done').length;

  return [
    {
      id: 'daily_login',
      icon: <Star size={20} />,
      name: 'Günlük Giriş',
      desc: 'Uygulamayı açtın, harika başlangıç!',
      xp: 10,
      color: 'text-green-400',
      bg: 'bg-green-500/10 border-green-500/20',
      done: true,
      progress: { current: 1, total: 1 },
    },
    {
      id: 'daily_record',
      icon: <Mic size={20} />,
      name: 'Ses Kaydı',
      desc: 'Bugün en az 1 ses kaydı yükle',
      xp: 50,
      color: 'text-blue-400',
      bg: 'bg-blue-500/10 border-blue-500/20',
      done: todayRecords.length >= 1,
      progress: { current: Math.min(todayRecords.length, 1), total: 1 },
    },
    {
      id: 'daily_task',
      icon: <Zap size={20} />,
      name: 'Aksiyon Tamamla',
      desc: 'Bugün en az 1 aksiyon tamamla',
      xp: 30,
      color: 'text-orange-400',
      bg: 'bg-orange-500/10 border-orange-500/20',
      done: todayDone.length >= 1,
      progress: { current: Math.min(todayDone.length, 1), total: 1 },
    },
    {
      id: 'daily_clear',
      icon: <Target size={20} />,
      name: 'Günü Temizle',
      desc: todayTasks.length === 0
        ? 'Bugün için planlanmış aksiyon yok'
        : `Bugünkü ${todayTasks.length} aksiyonu tamamla`,
      xp: todayTasks.length === 0 ? 0 : 100,
      color: 'text-purple-400',
      bg: 'bg-purple-500/10 border-purple-500/20',
      done: todayTasks.length > 0 && todayDone.length === todayTasks.length,
      progress: { current: todayDone.length, total: Math.max(todayTasks.length, 1) },
      disabled: todayTasks.length === 0,
    },
  ].filter(q => !q.disabled || q.id === 'daily_login');
};

// GENEL BAŞARIMLAR
const ACHIEVEMENTS = [
  {
    id: 'first_record',
    icon: <Mic size={24} />,
    name: 'İlk Adım',
    desc: 'İlk ses kaydını yükle',
    rarity: 'bronze',
    xp: 50,
    check: (r, t) => r.length >= 1,
    progress: (r, t) => ({ current: Math.min(r.length, 1), total: 1 }),
  },
  {
    id: 'three_records',
    icon: <BookOpen size={24} />,
    name: 'Düzenli Öğrenci',
    desc: '3 ses kaydı yükle',
    rarity: 'bronze',
    xp: 100,
    check: (r, t) => r.length >= 3,
    progress: (r, t) => ({ current: Math.min(r.length, 3), total: 3 }),
  },
  {
    id: 'ten_records',
    icon: <Crown size={24} />,
    name: 'Arşivci',
    desc: '10 ses kaydı yükle',
    rarity: 'silver',
    xp: 250,
    check: (r, t) => r.length >= 10,
    progress: (r, t) => ({ current: Math.min(r.length, 10), total: 10 }),
  },
  {
    id: 'first_task_done',
    icon: <CheckCircle2 size={24} />,
    name: 'İlk Tamamlama',
    desc: 'İlk aksiyonu tamamla',
    rarity: 'bronze',
    xp: 75,
    check: (r, t) => t.filter(x => x.status === 'done').length >= 1,
    progress: (r, t) => ({ current: Math.min(t.filter(x => x.status === 'done').length, 1), total: 1 }),
  },
  {
    id: 'five_tasks',
    icon: <Zap size={24} />,
    name: 'Momentum',
    desc: '5 aksiyon tamamla',
    rarity: 'silver',
    xp: 200,
    check: (r, t) => t.filter(x => x.status === 'done').length >= 5,
    progress: (r, t) => ({ current: Math.min(t.filter(x => x.status === 'done').length, 5), total: 5 }),
  },
  {
    id: 'twenty_tasks',
    icon: <Swords size={24} />,
    name: 'Aksiyon Makinesi',
    desc: '20 aksiyon tamamla',
    rarity: 'gold',
    xp: 400,
    check: (r, t) => t.filter(x => x.status === 'done').length >= 20,
    progress: (r, t) => ({ current: Math.min(t.filter(x => x.status === 'done').length, 20), total: 20 }),
  },
  {
    id: 'zero_tolerance',
    icon: <Shield size={24} />,
    name: 'Sıfır Tolerans',
    desc: 'Bekleyen hiçbir aksiyonun kalmasın',
    rarity: 'gold',
    xp: 350,
    check: (r, t) => t.length > 0 && t.every(x => x.status === 'done'),
    progress: (r, t) => ({ current: t.filter(x => x.status === 'done').length, total: Math.max(t.length, 1) }),
  },
  {
    id: 'night_owl',
    icon: <Star size={24} />,
    name: 'Gece Mesaisi',
    desc: 'Gece 00:00-05:00 arası kayıt yükle',
    rarity: 'epic',
    xp: 300,
    check: (r, t) => r.some(rec => { if (!rec.created_at) return false; const h = new Date(rec.created_at).getHours(); return h >= 0 && h < 5; }),
    progress: (r, t) => ({ current: r.some(rec => { if (!rec.created_at) return false; const h = new Date(rec.created_at).getHours(); return h >= 0 && h < 5; }) ? 1 : 0, total: 1 }),
  },
  {
    id: 'marathon',
    icon: <Flame size={24} />,
    name: 'Maraton',
    desc: 'Tek seferde 2000+ kelime transkript oluştur',
    rarity: 'epic',
    xp: 400,
    check: (r, t) => r.some(rec => rec.transcript && rec.transcript.split(' ').length >= 2000),
    progress: (r, t) => ({ current: Math.min(Math.max(...r.map(rec => rec.transcript ? rec.transcript.split(' ').length : 0), 0), 2000), total: 2000 }),
  },
  {
    id: 'early_bird',
    icon: <Star size={24} />,
    name: 'Erken Kalkan',
    desc: 'Bir aksiyonu bitiş tarihine 24+ saat kala tamamla',
    rarity: 'bronze',
    xp: 150,
    check: (r, t) => t.some(x => x.status === 'done' && x.due_date && (new Date(x.due_date) - new Date()) > 24 * 60 * 60 * 1000),
    progress: (r, t) => ({ current: t.filter(x => x.status === 'done' && x.due_date && (new Date(x.due_date) - new Date()) > 24 * 60 * 60 * 1000).length > 0 ? 1 : 0, total: 1 }),
  },
  {
    id: 'speed_clear',
    icon: <Zap size={24} />,
    name: 'Hız Makinesi',
    desc: 'Aynı gün 5 aksiyon tamamla',
    rarity: 'legendary',
    xp: 1000,
    check: (r, t) => { const today = new Date().toISOString().split('T')[0]; return t.filter(x => x.status === 'done' && x.due_date && x.due_date.substring(0,10) === today).length >= 5; },
    progress: (r, t) => { const today = new Date().toISOString().split('T')[0]; const count = t.filter(x => x.status === 'done' && x.due_date && x.due_date.substring(0,10) === today).length; return { current: Math.min(count, 5), total: 5 }; },
  },
];

const RARITY = {
  bronze:    { label:'Bronz',    border:'border-amber-600/50',   glow:'rgba(180,83,9,0.4)',    bg:'from-amber-900/20 to-transparent', icon:'text-amber-400',  badge:'bg-amber-900/50 text-amber-300' },
  silver:    { label:'Gümüş',   border:'border-slate-400/50',   glow:'rgba(148,163,184,0.3)', bg:'from-slate-700/20 to-transparent', icon:'text-slate-300',  badge:'bg-slate-700/50 text-slate-300' },
  gold:      { label:'Altın',   border:'border-yellow-400/60',  glow:'rgba(250,204,21,0.4)',  bg:'from-yellow-900/20 to-transparent', icon:'text-yellow-400', badge:'bg-yellow-900/50 text-yellow-300' },
  epic:      { label:'Epik',    border:'border-purple-400/60',  glow:'rgba(168,85,247,0.4)',  bg:'from-purple-900/20 to-transparent', icon:'text-purple-400', badge:'bg-purple-900/50 text-purple-300' },
  legendary: { label:'Efsanevi',border:'border-orange-400/60',  glow:'rgba(251,146,60,0.5)',  bg:'from-orange-900/20 to-transparent', icon:'text-orange-400', badge:'bg-orange-900/50 text-orange-300' },
};

export default function StatsView({ records, tasks }) {
  const [activeTab, setActiveTab] = useState('daily');

  const dailyQuests = getDailyQuests(records, tasks);
  const dailyXP = dailyQuests.filter(q => q.done).reduce((s,q) => s+q.xp, 0);
  const dailyMaxXP = dailyQuests.reduce((s,q) => s+q.xp, 0);
  const dailyDone = dailyQuests.filter(q => q.done).length;

  const unlockedAchievements = ACHIEVEMENTS.filter(a => a.check(records, tasks));
  const totalXP = unlockedAchievements.reduce((s,a) => s+a.xp, 0) + dailyXP;
  const maxXP = ACHIEVEMENTS.reduce((s,a) => s+a.xp, 0) + dailyMaxXP;
  const xpPercent = Math.round((totalXP / maxXP) * 100);
  const level = totalXP < 200 ? 1 : totalXP < 500 ? 2 : totalXP < 1000 ? 3 : totalXP < 2000 ? 4 : 5;
  const levelNames = ['','Acemi','Meraklı','Avcı','Usta','Efsane'];

  const today = new Date().toISOString().split('T')[0];
  const todayTasks = tasks.filter(t => t.due_date && t.due_date.substring(0,10) === today);
  const todayDone = todayTasks.filter(t => t.status === 'done');

  return (
    <div className="p-8 max-w-5xl mx-auto">

      {/* Profil Kartı */}
      <motion.div
        initial={{ opacity:0, y:20 }} animate={{ opacity:1, y:0 }}
        className="relative overflow-hidden bg-gradient-to-br from-slate-900 to-slate-800 border border-slate-700/50 rounded-3xl p-6 mb-8"
        style={{ boxShadow:'0 0 40px rgba(99,102,241,0.15)' }}
      >
        <div className="absolute top-0 right-0 w-64 h-64 bg-gradient-to-bl from-indigo-600/10 to-transparent rounded-full blur-3xl pointer-events-none" />
        <div className="flex items-center gap-6">
          <div className="relative flex-shrink-0">
            <motion.div
              animate={{ boxShadow: ['0 0 15px rgba(99,102,241,0.4)','0 0 30px rgba(99,102,241,0.7)','0 0 15px rgba(99,102,241,0.4)'] }}
              transition={{ repeat:Infinity, duration:3 }}
              className="w-20 h-20 rounded-2xl bg-gradient-to-br from-blue-600 to-indigo-600 flex items-center justify-center text-3xl font-black text-white"
            >
              {localStorage.getItem('userName')?.charAt(0).toUpperCase() || 'U'}
            </motion.div>
            <div className="absolute -bottom-2 -right-2 w-8 h-8 rounded-full bg-gradient-to-br from-yellow-400 to-orange-400 flex items-center justify-center text-xs font-black text-black shadow-lg">
              {level}
            </div>
          </div>
          <div className="flex-1">
            <div className="flex items-center gap-2 mb-1">
              <p className="text-slate-400 text-xs uppercase tracking-widest font-semibold">Seviye {level}</p>
              <span className="text-xs px-2 py-0.5 rounded-full bg-indigo-600/20 text-indigo-300 border border-indigo-500/20 font-semibold">{levelNames[level]}</span>
            </div>
            <p className="text-white font-bold text-lg mb-3">{localStorage.getItem('userName') || 'Kullanıcı'}</p>
            <div>
              <div className="flex justify-between text-xs text-slate-500 mb-1.5">
                <span className="text-indigo-400 font-semibold">{totalXP} XP</span>
                <span>{maxXP} XP</span>
              </div>
              <div className="h-2.5 bg-slate-700/50 rounded-full overflow-hidden">
                <motion.div
                  initial={{ width:0 }} animate={{ width:`${xpPercent}%` }}
                  transition={{ duration:1.5, ease:'easeOut' }}
                  className="h-full rounded-full bg-gradient-to-r from-blue-500 via-indigo-500 to-purple-500"
                  style={{ boxShadow:'0 0 10px rgba(99,102,241,0.6)' }}
                />
              </div>
            </div>
          </div>
          <div className="text-center flex-shrink-0">
            <div className="text-4xl font-black text-yellow-400">{unlockedAchievements.length}</div>
            <div className="text-xs text-slate-400 mt-1">/ {ACHIEVEMENTS.length}</div>
            <div className="text-xs text-slate-500">Başarım</div>
          </div>
        </div>

        {/* Hızlı istatistikler */}
        <div className="grid grid-cols-4 gap-3 mt-6 pt-6 border-t border-slate-700/50">
          {[
            { icon:<Mic size={16}/>, label:'Kayıt', value:records.length, color:'text-blue-400' },
            { icon:<Zap size={16}/>, label:'Toplam Aksiyon', value:tasks.length, color:'text-orange-400' },
            { icon:<CheckCircle2 size={16}/>, label:'Tamamlanan', value:tasks.filter(t=>t.status==='done').length, color:'text-green-400' },
            { icon:<Calendar size={16}/>, label:'Bugün', value:`${todayDone.length}/${todayTasks.length}`, color:'text-purple-400' },
          ].map(s => (
            <div key={s.label} className="text-center">
              <div className={`flex justify-center mb-1 ${s.color}`}>{s.icon}</div>
              <div className={`text-xl font-extrabold ${s.color}`}>{s.value}</div>
              <div className="text-xs text-slate-500">{s.label}</div>
            </div>
          ))}
        </div>
      </motion.div>

      {/* Tab seçici */}
      <div className="flex gap-2 mb-6">
        {[
          { key:'daily', label:'Günlük Görevler', icon:<Flame size={16}/> },
          { key:'achievements', label:'Başarımlar', icon:<Trophy size={16}/> },
        ].map(tab => (
          <button key={tab.key} onClick={() => setActiveTab(tab.key)}
            className={`flex items-center gap-2 px-5 py-2.5 rounded-xl font-semibold text-sm transition-all ${
              activeTab === tab.key
                ? 'bg-blue-600 text-white shadow-lg shadow-blue-600/20'
                : 'bg-slate-800/50 text-slate-400 hover:bg-slate-700 border border-slate-700'
            }`}>
            {tab.icon}{tab.label}
          </button>
        ))}
      </div>

      <AnimatePresence mode="wait">
        {activeTab === 'daily' && (
          <motion.div key="daily" initial={{opacity:0,x:-20}} animate={{opacity:1,x:0}} exit={{opacity:0,x:20}}>
            {/* Günlük progress */}
            <div className="bg-slate-900/60 border border-slate-700/50 rounded-2xl p-4 mb-6">
              <div className="flex items-center justify-between mb-3">
                <div className="flex items-center gap-2">
                  <Flame size={18} className="text-orange-400" />
                  <span className="font-bold text-white text-sm">Bugünkü İlerleme</span>
                </div>
                <span className="text-orange-400 font-bold text-sm">{dailyDone}/{dailyQuests.length} görev</span>
              </div>
              <div className="h-2 bg-slate-700 rounded-full overflow-hidden">
                <motion.div
                  initial={{width:0}} animate={{width:`${(dailyDone/dailyQuests.length)*100}%`}}
                  transition={{duration:1}}
                  className="h-full rounded-full bg-gradient-to-r from-orange-400 to-yellow-400"
                  style={{boxShadow:'0 0 8px rgba(251,146,60,0.6)'}}
                />
              </div>
              <p className="text-xs text-slate-500 mt-2">Bugün kazanılabilecek XP: +{dailyMaxXP - dailyXP} XP</p>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {dailyQuests.map((quest, i) => (
                <motion.div
                  key={quest.id}
                  initial={{opacity:0, y:10}} animate={{opacity:1, y:0}}
                  transition={{delay:i*0.1}}
                  whileHover={{scale:1.02}}
                  className={`relative p-5 rounded-2xl border transition-all ${
                    quest.done
                      ? 'bg-green-950/30 border-green-500/30'
                      : `${quest.bg} border`
                  }`}
                  style={quest.done ? {boxShadow:'0 0 15px rgba(74,222,128,0.15)'} : {}}
                >
                  <div className="flex items-start gap-4">
                    <div className={`p-2.5 rounded-xl ${quest.done ? 'bg-green-500/20 text-green-400' : `bg-slate-800 ${quest.color}`}`}>
                      {quest.done ? <CheckCircle2 size={20} /> : quest.icon}
                    </div>
                    <div className="flex-1">
                      <div className="flex items-center justify-between mb-1">
                        <h3 className={`font-bold text-sm ${quest.done ? 'text-green-300 line-through' : 'text-white'}`}>
                          {quest.name}
                        </h3>
                        <span className={`text-xs font-bold px-2 py-0.5 rounded-full ${quest.done ? 'bg-green-500/20 text-green-400' : 'bg-yellow-500/10 text-yellow-400'}`}>
                          +{quest.xp} XP
                        </span>
                      </div>
                      <p className="text-xs text-slate-400 mb-3">{quest.desc}</p>
                      <div>
                        <div className="flex justify-between text-xs text-slate-500 mb-1">
                          <span>{quest.progress.current}/{quest.progress.total}</span>
                          <span>{Math.round((quest.progress.current/quest.progress.total)*100)}%</span>
                        </div>
                        <div className="h-1.5 bg-slate-700/50 rounded-full overflow-hidden">
                          <motion.div
                            initial={{width:0}}
                            animate={{width:`${(quest.progress.current/quest.progress.total)*100}%`}}
                            transition={{duration:0.8, delay:i*0.1}}
                            className={`h-full rounded-full ${quest.done ? 'bg-green-400' : 'bg-gradient-to-r from-blue-400 to-indigo-400'}`}
                          />
                        </div>
                      </div>
                    </div>
                  </div>
                  {quest.done && (
                    <motion.div
                      initial={{scale:0}} animate={{scale:1}}
                      className="absolute top-3 right-3"
                    >
                      <Star size={16} className="text-yellow-400 fill-yellow-400" />
                    </motion.div>
                  )}
                </motion.div>
              ))}
            </div>
          </motion.div>
        )}

        {activeTab === 'achievements' && (
          <motion.div key="achievements" initial={{opacity:0,x:20}} animate={{opacity:1,x:0}} exit={{opacity:0,x:-20}}>
            <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
              {ACHIEVEMENTS.map((a, i) => {
                const unlocked = a.check(records, tasks);
                const prog = a.progress(records, tasks);
                const pct = Math.round((prog.current/prog.total)*100);
                const s = RARITY[a.rarity];
                return (
                  <motion.div
                    key={a.id}
                    initial={{opacity:0, scale:0.9}} animate={{opacity:1, scale:1}}
                    transition={{delay:i*0.05}}
                    whileHover={unlocked ? {scale:1.05, y:-4} : {scale:1.01}}
                    className={`relative rounded-2xl border p-4 transition-all ${
                      unlocked ? `bg-gradient-to-br ${s.bg} ${s.border}` : 'bg-slate-900/40 border-slate-800/50 grayscale opacity-40'
                    }`}
                    style={unlocked ? {boxShadow:`0 0 20px ${s.glow}`} : {}}
                  >
                    {!unlocked && <Lock size={12} className="absolute top-2 right-2 text-slate-600" />}
                    {unlocked && (
                      <motion.div animate={{rotate:[0,10,-10,0]}} transition={{repeat:Infinity,duration:3,delay:i*0.2}} className="absolute top-2 right-2">
                        <Star size={12} className="text-yellow-400 fill-yellow-400" />
                      </motion.div>
                    )}
                    <div className={`mb-2 ${unlocked ? s.icon : 'text-slate-600'}`}>{a.icon}</div>
                    <span className={`text-[10px] font-bold px-1.5 py-0.5 rounded-full ${unlocked ? s.badge : 'bg-slate-800 text-slate-600'}`}>{s.label}</span>
                    <h3 className={`font-bold text-xs mt-2 mb-1 ${unlocked ? 'text-white' : 'text-slate-600'}`}>{a.name}</h3>
                    <p className={`text-[10px] mb-2 leading-relaxed ${unlocked ? 'text-slate-400' : 'text-slate-600'}`}>{a.desc}</p>
                    <div className="h-1 bg-slate-700/50 rounded-full overflow-hidden mb-1">
                      <motion.div
                        initial={{width:0}} animate={{width:`${pct}%`}}
                        transition={{duration:0.8, delay:i*0.05}}
                        className={`h-full rounded-full ${unlocked ? 'bg-gradient-to-r from-yellow-400 to-orange-400' : 'bg-slate-600'}`}
                      />
                    </div>
                    <div className="flex justify-between text-[10px] text-slate-500">
                      <span>{prog.current}/{prog.total}</span>
                      {unlocked && <span className="text-yellow-400 font-bold">+{a.xp}XP</span>}
                    </div>
                  </motion.div>
                );
              })}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
