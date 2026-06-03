import { useState, useEffect, useCallback } from 'react';
import { motion } from 'framer-motion';
import { Zap, Flame, Clock, CheckCircle2, Trash2, Circle, Folder } from 'lucide-react';
import api from '../api';

const getUrgencyIcon = (dueDate) => {
  if (!dueDate) return <Clock size={12} />;
  const diff = (new Date(dueDate) - new Date()) / (1000 * 60 * 60 * 24);
  if (diff < 0 || diff <= 1) return <Flame size={12} />;
  return <Clock size={12} />;
};

export default function TasksView({ tasks, onToggle, onDelete }) {
  const [filter, setFilter] = useState('all');
  const [activeTimer, setActiveTimer] = useState({ taskId: null, timeLeft: 1500, isRunning: false, originalTime: 1500 });

  useEffect(() => {
    if (!activeTimer.isRunning) return;
    const interval = setInterval(() => {
      setActiveTimer(prev => {
        if (prev.timeLeft <= 1) {
          clearInterval(interval);
          return { ...prev, timeLeft: 0, isRunning: false };
        }
        return { ...prev, timeLeft: prev.timeLeft - 1 };
      });
    }, 1000);
    return () => clearInterval(interval);
  }, [activeTimer.isRunning]);

  const formatTime = (secs) => {
    const m = Math.floor(secs / 60).toString().padStart(2, '0');
    const s = (secs % 60).toString().padStart(2, '0');
    return `${m}:${s}`;
  };

  const sorted = [...tasks].sort((a, b) => {
    if (a.status === 'done' && b.status !== 'done') return 1;
    if (a.status !== 'done' && b.status === 'done') return -1;
    return 0;
  });

  const filteredByStatus = filter === 'all' ? sorted
    : filter === 'pending' ? sorted.filter(t => t.status !== 'done')
    : sorted.filter(t => t.status === 'done');

  const tasksByRecord = filteredByStatus.reduce((acc, task) => {
    const key = task.record_id || 'other';
    const label = task.file_name || task.record_name || `Kayıt #${task.record_id}` || 'Diğer';
    if (!acc[key]) acc[key] = { label, category: task.category || 'Diğer', tasks: [] };
    acc[key].tasks.push(task);
    return acc;
  }, {});

  const handleToggle = async (id) => {
    await api.toggleTask(id);
    onToggle();
  };

  const handleDelete = async (id) => {
    await api.deleteTask(id);
    onDelete();
  };

  const urgencyColor = (dueDate) => {
    if (!dueDate) return 'text-slate-400';
    const diff = (new Date(dueDate) - new Date()) / (1000 * 60 * 60 * 24);
    if (diff < 0) return 'text-red-400';
    if (diff <= 1) return 'text-orange-400';
    if (diff <= 7) return 'text-blue-400';
    return 'text-slate-400';
  };

  return (
    <div className="p-8 max-w-4xl mx-auto">
      <div className="flex items-center justify-between mb-8">
        <div>
          <h1 className="text-3xl font-extrabold text-white flex items-center gap-2">
            <Zap size={28} className="text-orange-400" /> Aksiyonlar
          </h1>
          <p className="text-slate-400 text-sm mt-1">
            {tasks.filter(t => t.status !== 'done').length} bekleyen · {tasks.filter(t => t.status === 'done').length} tamamlanan
          </p>
        </div>
        <div className="flex gap-2">
          {[
            { key: 'all',     label: 'Tümü',       count: tasks.length },
            { key: 'pending', label: 'Bekleyen',   count: tasks.filter(t => t.status !== 'done').length },
            { key: 'done',    label: 'Tamamlanan', count: tasks.filter(t => t.status === 'done').length },
          ].map(f => (
            <button
              key={f.key}
              onClick={() => setFilter(f.key)}
              className={`px-3 py-2 rounded-xl text-xs font-semibold transition flex items-center gap-1.5 ${
                filter === f.key
                  ? 'bg-blue-600 text-white shadow-lg shadow-blue-600/20'
                  : 'bg-slate-800 text-slate-400 hover:text-white hover:bg-slate-700'
              }`}
            >
              {f.label}
              <span className={`px-1.5 py-0.5 rounded-full text-[10px] font-bold ${filter === f.key ? 'bg-blue-500/50' : 'bg-slate-700'}`}>{f.count}</span>
            </button>
          ))}
        </div>
      </div>

      {filteredByStatus.length === 0 ? (
        <div className="text-center py-20 text-slate-500">
          <Zap size={48} className="text-slate-600 mb-4 mx-auto" />
          <p className="font-semibold">Henüz aksiyon yok</p>
          <p className="text-sm mt-1">Ses kaydı yükleyin, AI otomatik çıkarsın</p>
        </div>
      ) : (
        <div>
          {Object.entries(tasksByRecord).map(([recordId, group]) => (
            <div key={recordId} className="mb-6">
              <div className="flex items-center gap-2 mb-3">
                <div className="flex items-center gap-2 px-3 py-1.5 bg-slate-800 border border-slate-700 rounded-xl">
                  <Folder size={14} className="text-blue-400" />
                  <span className="text-sm font-semibold text-slate-300">{group.label}</span>
                  <span className="text-xs px-2 py-0.5 rounded-full bg-slate-700 text-slate-400">{group.category}</span>
                  <span className="text-xs px-2 py-0.5 rounded-full bg-blue-600/20 text-blue-400">{group.tasks.length} aksiyon</span>
                </div>
              </div>
              <div className="space-y-2 pl-2 border-l-2 border-slate-800">
                {group.tasks.map((t, index) => {
                  const isDone = t.status === 'done';
                  return (
                    <motion.div
                      key={t.id}
                      initial={{ opacity: 0, y: 10 }}
                      animate={{ opacity: 1, y: 0 }}
                      transition={{ duration: 0.3, delay: index * 0.05 }}
                      whileHover={{ scale: 1.01 }}
                      className="backdrop-blur-sm bg-slate-900/60 border border-slate-700/50 rounded-2xl p-4 hover:border-slate-600 transition-all duration-300"
                    >
                      <div className="flex items-start gap-4">
                        <button
                          onClick={() => handleToggle(t.id)}
                          className={`w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0 mt-0.5 transition-all duration-300 active:scale-75 ${isDone ? 'bg-green-500/20 text-green-400 ring-2 ring-green-500/20' : 'bg-slate-700 hover:bg-blue-500/20 text-slate-400 hover:text-blue-400'}`}
                        >
                          {isDone ? <CheckCircle2 size={16} /> : <Circle size={16} />}
                        </button>
                        <div className="flex-1 min-w-0">
                          <p className={`text-sm font-semibold transition-all duration-300 ${isDone ? 'line-through text-slate-500' : 'text-white'}`}>
                            {t.title}
                          </p>
                          {t.due_date && (
                            <p className={`flex items-center gap-1 text-xs mt-1 font-medium ${urgencyColor(t.due_date)}`}>
                              {getUrgencyIcon(t.due_date)} {new Date(t.due_date).toLocaleDateString('tr-TR')}
                            </p>
                          )}
                          <p className="text-xs text-slate-500 mt-1">✨ AI tespit etti</p>
                        </div>
                        {!isDone && (
                          <button
                            onClick={() => setActiveTimer(prev =>
                              prev.taskId === t.id
                                ? { taskId: null, timeLeft: 1500, isRunning: false, originalTime: 1500 }
                                : { taskId: t.id, timeLeft: 1500, isRunning: false, originalTime: 1500 }
                            )}
                            className={`w-8 h-8 rounded-xl flex items-center justify-center text-sm transition ${
                              activeTimer.taskId === t.id
                                ? 'bg-purple-600/30 text-purple-400'
                                : 'bg-slate-800 hover:bg-purple-600/20 text-slate-500 hover:text-purple-400'
                            }`}
                            title="Pomodoro Başlat"
                          >
                            ⏱
                          </button>
                        )}
                        <button
                          onClick={() => handleDelete(t.id)}
                          className="w-8 h-8 rounded-xl bg-slate-800 hover:bg-red-900/30 text-slate-500 hover:text-red-400 flex items-center justify-center transition"
                        >
                          <Trash2 size={14} />
                        </button>
                      </div>
                      {activeTimer.taskId === t.id && (
                        <div className="mt-4 pt-4 border-t border-slate-700/50">
                          {activeTimer.timeLeft === 0 ? (
                            <div className="text-center">
                              <p className="text-green-400 font-bold text-sm mb-3">🎉 Süre Bitti! Harika odaklandın.</p>
                              <button
                                onClick={() => { handleToggle(t.id); setActiveTimer({ taskId: null, timeLeft: 1500, isRunning: false, originalTime: 1500 }); }}
                                className="w-full py-2 bg-green-600/20 hover:bg-green-600/30 border border-green-500/30 rounded-xl text-green-400 text-xs font-bold transition"
                              >
                                ✅ Görevi Tamamlandı Olarak İşaretle
                              </button>
                            </div>
                          ) : (
                            <>
                              <div className="flex gap-2 mb-3 justify-center">
                                {[15, 25, 50].map(min => (
                                  <button
                                    key={min}
                                    onClick={() => setActiveTimer(prev => ({ ...prev, timeLeft: min * 60, originalTime: min * 60, isRunning: false }))}
                                    className={`px-3 py-1 rounded-lg text-xs font-bold transition ${
                                      activeTimer.originalTime === min * 60
                                        ? 'bg-purple-600 text-white'
                                        : 'bg-slate-800 text-slate-400 hover:bg-slate-700 border border-slate-700'
                                    }`}
                                  >
                                    {min} dk
                                  </button>
                                ))}
                                <button
                                  onClick={() => setActiveTimer(prev => ({ ...prev, timeLeft: Math.max(60, prev.timeLeft - 300), originalTime: Math.max(60, prev.originalTime - 300) }))}
                                  className="px-2 py-1 rounded-lg text-xs font-bold bg-slate-800 text-slate-400 hover:bg-slate-700 border border-slate-700"
                                >-5</button>
                                <button
                                  onClick={() => setActiveTimer(prev => ({ ...prev, timeLeft: prev.timeLeft + 300, originalTime: prev.originalTime + 300 }))}
                                  className="px-2 py-1 rounded-lg text-xs font-bold bg-slate-800 text-slate-400 hover:bg-slate-700 border border-slate-700"
                                >+5</button>
                              </div>
                              <div className="text-center mb-3">
                                <span style={{ fontFamily: 'monospace', fontSize: '2.5rem', fontWeight: '900', letterSpacing: '0.1em' }}
                                  className={`${activeTimer.isRunning ? 'text-purple-400' : 'text-slate-300'}`}>
                                  {formatTime(activeTimer.timeLeft)}
                                </span>
                                <div className="h-1.5 bg-slate-700 rounded-full mt-2 overflow-hidden">
                                  <div
                                    className="h-full bg-gradient-to-r from-purple-500 to-indigo-500 rounded-full transition-all duration-1000"
                                    style={{ width: `${(activeTimer.timeLeft / activeTimer.originalTime) * 100}%` }}
                                  />
                                </div>
                              </div>
                              <div className="flex gap-2 justify-center">
                                <button
                                  onClick={() => setActiveTimer(prev => ({ ...prev, isRunning: !prev.isRunning }))}
                                  className={`flex-1 py-2 rounded-xl text-xs font-bold transition ${
                                    activeTimer.isRunning
                                      ? 'bg-yellow-600/20 hover:bg-yellow-600/30 border border-yellow-500/30 text-yellow-400'
                                      : 'bg-purple-600/20 hover:bg-purple-600/30 border border-purple-500/30 text-purple-400'
                                  }`}
                                >
                                  {activeTimer.isRunning ? '⏸ Duraklat' : '▶ Başlat'}
                                </button>
                                <button
                                  onClick={() => setActiveTimer({ taskId: null, timeLeft: 1500, isRunning: false, originalTime: 1500 })}
                                  className="px-4 py-2 rounded-xl text-xs font-bold bg-slate-800 hover:bg-red-900/20 border border-slate-700 hover:border-red-500/30 text-slate-400 hover:text-red-400 transition"
                                >
                                  ✕ İptal
                                </button>
                              </div>
                            </>
                          )}
                        </div>
                      )}
                    </motion.div>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
