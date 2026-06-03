import { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { ChevronLeft, ChevronRight, Flame, CheckCircle2, Clock, AlertCircle } from 'lucide-react';

const DAYS = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
const MONTHS = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];

export default function CalendarView({ tasks, onNavigate }) {
  const [currentDate, setCurrentDate] = useState(new Date());
  const [selectedDay, setSelectedDay] = useState(new Date());

  const year = currentDate.getFullYear();
  const month = currentDate.getMonth();
  const firstDay = new Date(year, month, 1).getDay();
  const adjustedFirst = firstDay === 0 ? 6 : firstDay - 1;
  const daysInMonth = new Date(year, month + 1, 0).getDate();

  const today = new Date();
  const todayStr = `${today.getFullYear()}-${String(today.getMonth()+1).padStart(2,'0')}-${String(today.getDate()).padStart(2,'0')}`;

  const tasksByDate = tasks.reduce((acc, t) => {
    if (!t.due_date) return acc;
    const d = t.due_date.substring(0, 10);
    if (!acc[d]) acc[d] = [];
    acc[d].push(t);
    return acc;
  }, {});

  const pad = n => String(n).padStart(2, '0');
  const selectedDateStr = `${selectedDay.getFullYear()}-${pad(selectedDay.getMonth()+1)}-${pad(selectedDay.getDate())}`;
  const selectedTasks = tasksByDate[selectedDateStr] || [];

  const getDayStatus = (dateStr) => {
    const dayTasks = tasksByDate[dateStr];
    if (!dayTasks || dayTasks.length === 0) return null;
    const allDone = dayTasks.every(t => t.status === 'done');
    const isPast = dateStr < todayStr;
    const hasPending = dayTasks.some(t => t.status !== 'done');
    if (allDone) return 'done';
    if (isPast && hasPending) return 'overdue';
    if (dateStr === todayStr) return 'today-tasks';
    return 'pending';
  };

  const statusColors = {
    done: { dot: 'bg-green-400', glow: '0 0 8px rgba(74, 222, 128, 0.6)', ring: 'ring-green-500/30' },
    overdue: { dot: 'bg-red-400', glow: '0 0 8px rgba(248, 113, 113, 0.6)', ring: 'ring-red-500/30' },
    'today-tasks': { dot: 'bg-orange-400', glow: '0 0 8px rgba(251, 146, 60, 0.6)', ring: 'ring-orange-500/30' },
    pending: { dot: 'bg-blue-400', glow: '0 0 8px rgba(96, 165, 250, 0.6)', ring: 'ring-blue-500/30' },
  };

  return (
    <div className="p-8 max-w-4xl mx-auto">
      <h1 className="text-3xl font-extrabold text-white mb-2 flex items-center gap-2">
        📅 Aksiyon Takvimi
      </h1>
      <p className="text-slate-400 text-sm mb-8">Aksiyonlarınızı takvimde görüntüleyin</p>

      {/* Renk legend */}
      <div className="flex gap-4 mb-6 flex-wrap">
        {[
          { color: 'bg-green-400', label: 'Tamamlandı', glow: 'shadow-green-400/50' },
          { color: 'bg-blue-400', label: 'Bekliyor', glow: 'shadow-blue-400/50' },
          { color: 'bg-orange-400', label: 'Bugün', glow: 'shadow-orange-400/50' },
          { color: 'bg-red-400', label: 'Geçti & Bekliyor', glow: 'shadow-red-400/50' },
        ].map(item => (
          <div key={item.label} className="flex items-center gap-2">
            <div className={`w-3 h-3 rounded-full ${item.color} shadow-md ${item.glow}`} />
            <span className="text-xs text-slate-400 font-medium">{item.label}</span>
          </div>
        ))}
      </div>

      <div className="bg-slate-900/60 backdrop-blur border border-slate-700/50 rounded-2xl p-6 mb-6">
        {/* Header */}
        <div className="flex items-center justify-between mb-6">
          <motion.button
            whileHover={{ scale: 1.1 }} whileTap={{ scale: 0.9 }}
            onClick={() => setCurrentDate(new Date(year, month - 1, 1))}
            className="w-10 h-10 rounded-xl bg-slate-800 hover:bg-slate-700 flex items-center justify-center text-slate-400 hover:text-white transition"
          >
            <ChevronLeft size={18} />
          </motion.button>
          <h2 className="font-bold text-white text-xl">{MONTHS[month]} {year}</h2>
          <motion.button
            whileHover={{ scale: 1.1 }} whileTap={{ scale: 0.9 }}
            onClick={() => setCurrentDate(new Date(year, month + 1, 1))}
            className="w-10 h-10 rounded-xl bg-slate-800 hover:bg-slate-700 flex items-center justify-center text-slate-400 hover:text-white transition"
          >
            <ChevronRight size={18} />
          </motion.button>
        </div>

        {/* Gün isimleri */}
        <div className="grid grid-cols-7 gap-0.5 mb-2">
          {DAYS.map(d => (
            <div key={d} className="text-center text-xs font-bold text-slate-600 py-2 uppercase tracking-widest">{d}</div>
          ))}
        </div>

        {/* Günler */}
        <div className="grid grid-cols-7 gap-0.5">
          {Array(adjustedFirst).fill(null).map((_, i) => <div key={`e${i}`} />)}
          {Array(daysInMonth).fill(null).map((_, i) => {
            const day = i + 1;
            const dateStr = `${year}-${pad(month+1)}-${pad(day)}`;
            const isToday = dateStr === todayStr;
            const isSelected = dateStr === selectedDateStr;
            const status = getDayStatus(dateStr);
            const dayTasks = tasksByDate[dateStr] || [];
            const overdueCount = dayTasks.filter(t => t.status !== 'done' && dateStr < todayStr).length;
            const pendingCount = dayTasks.filter(t => t.status !== 'done' && dateStr >= todayStr).length;
            const doneCount = dayTasks.filter(t => t.status === 'done').length;

            return (
              <motion.button
                key={day}
                whileHover={{ scale: 1.05 }}
                whileTap={{ scale: 0.95 }}
                onClick={() => setSelectedDay(new Date(year, month, day))}
                className="relative flex flex-col items-start p-2 rounded-xl border border-white/5 hover:border-slate-600/50 hover:bg-slate-800/30 transition-all duration-200 min-h-[52px]"
                style={{ background: 'transparent' }}
              >
                {/* Gün numarası */}
                <div className={`w-7 h-7 flex items-center justify-center rounded-full text-sm font-semibold transition-all ${
                  isSelected
                    ? 'bg-blue-600 text-white shadow-lg shadow-blue-500/40'
                    : isToday
                    ? 'bg-slate-700 text-white ring-2 ring-blue-400/60'
                    : status === 'overdue'
                    ? 'text-red-400 font-bold'
                    : status === 'done'
                    ? 'text-emerald-400'
                    : 'text-slate-300'
                }`}>
                  {day}
                </div>

                {/* Görev noktaları */}
                {dayTasks.length > 0 && (
                  <div className="flex gap-0.5 mt-1 px-0.5">
                    {overdueCount > 0 && (
                      <motion.div
                        className="w-1.5 h-1.5 rounded-full bg-red-500"
                        animate={{ opacity: [1, 0.3, 1] }}
                        transition={{ repeat: Infinity, duration: 1.5 }}
                        style={{ boxShadow: '0 0 4px rgba(239,68,68,0.8)' }}
                      />
                    )}
                    {pendingCount > 0 && (
                      <div
                        className="w-1.5 h-1.5 rounded-full bg-blue-400"
                        style={{ boxShadow: '0 0 4px rgba(96,165,250,0.6)' }}
                      />
                    )}
                    {doneCount > 0 && (
                      <div
                        className="w-1.5 h-1.5 rounded-full bg-emerald-400"
                        style={{ boxShadow: '0 0 4px rgba(52,211,153,0.6)' }}
                      />
                    )}
                  </div>
                )}
              </motion.button>
            );
          })}
        </div>
      </div>

      {/* Seçili gün */}
      <AnimatePresence mode="wait">
        <motion.div
          key={selectedDateStr}
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: -10 }}
          transition={{ duration: 0.2 }}
        >
          <div className="flex items-center justify-between mb-4">
            <h3 className="font-bold text-white text-lg">
              {selectedDay.toLocaleDateString('tr-TR', { weekday: 'long', day: 'numeric', month: 'long' })}
            </h3>
            {selectedTasks.length > 0 && (
              <span className="text-sm bg-blue-500/20 text-blue-400 px-3 py-1 rounded-full font-semibold border border-blue-500/20">
                {selectedTasks.length} aksiyon
              </span>
            )}
          </div>

          {selectedTasks.length === 0 ? (
            <div className="text-center py-12 text-slate-600">
              <div className="text-4xl mb-3">📭</div>
              <p className="text-sm font-medium">Bu gün için aksiyon yok</p>
            </div>
          ) : (
            <div className="space-y-3">
              {selectedTasks.map((t, i) => {
                const isDone = t.status === 'done';
                const isPast = selectedDateStr < todayStr;
                const isOverdue = isPast && !isDone;

                return (
                  <motion.div
                    key={t.id}
                    initial={{ opacity: 0, x: -10 }}
                    animate={{ opacity: 1, x: 0 }}
                    transition={{ delay: i * 0.05 }}
                    className={`p-4 rounded-2xl border transition-all cursor-pointer ${
                      isDone ? 'bg-green-950/20 border-green-500/20' :
                      isOverdue ? 'bg-red-950/20 border-red-500/20' :
                      'bg-slate-900 border-slate-700 hover:border-blue-500/30'
                    }`}
                    style={{
                      boxShadow: isDone ? '0 0 12px rgba(74,222,128,0.1)' :
                                 isOverdue ? '0 0 12px rgba(248,113,113,0.1)' : 'none'
                    }}
                    onClick={() => setSelectedDay(prev => prev)}
                  >
                    <div className="flex items-center gap-3">
                      <motion.div
                        animate={isOverdue ? { scale: [1, 1.2, 1] } : {}}
                        transition={{ repeat: Infinity, duration: 2 }}
                      >
                        {isDone ? <CheckCircle2 size={20} className="text-green-400" /> :
                         isOverdue ? <AlertCircle size={20} className="text-red-400" /> :
                         <Clock size={20} className="text-blue-400" />}
                      </motion.div>
                      <div className="flex-1 min-w-0">
                        <p className={`text-sm font-semibold ${isDone ? 'line-through text-slate-500' : isOverdue ? 'text-red-300' : 'text-white'}`}>
                          {t.title}
                        </p>
                        <p className="text-xs mt-0.5 text-slate-500">
                          {isDone ? '✅ Tamamlandı' : isOverdue ? '⚠️ Gecikti' : '⏳ Bekliyor'}
                        </p>
                      </div>
                      <span className={`text-xs px-2 py-1 rounded-full font-semibold ${
                        isDone ? 'bg-green-500/10 text-green-400' :
                        isOverdue ? 'bg-red-500/10 text-red-400' :
                        'bg-blue-500/10 text-blue-400'
                      }`}>
                        {t.category || 'Diğer'}
                      </span>
                    </div>

                    <div className="flex gap-2 mt-3">
                      <button
                        onClick={e => { e.stopPropagation(); onNavigate('tasks'); }}
                        className="flex-1 py-1.5 bg-slate-800 hover:bg-slate-700 border border-slate-600 rounded-xl text-xs font-semibold text-slate-300 transition"
                      >
                        Listede Göster
                      </button>
                      <button
                        onClick={e => { e.stopPropagation(); onNavigate('records'); }}
                        className="flex-1 py-1.5 bg-blue-600/20 hover:bg-blue-600/30 border border-blue-500/30 rounded-xl text-xs font-semibold text-blue-400 transition"
                      >
                        Kaydı Aç
                      </button>
                    </div>
                  </motion.div>
                );
              })}
            </div>
          )}
        </motion.div>
      </AnimatePresence>
    </div>
  );
}
