import { useState, useEffect } from 'react';
import api from '../api';
import Sidebar from '../components/Sidebar';
import HomeView from '../components/HomeView';
import TasksView from '../components/TasksView';
import RecordsView from '../components/RecordsView';
import CalendarView from '../components/CalendarView';
import ChatView from '../components/ChatView';
import StatsView from '../components/StatsView';

export default function Dashboard({ onLogout }) {
  const [activeTab, setActiveTab] = useState('home');
  const [records, setRecords] = useState([]);
  const [tasks, setTasks] = useState([]);
  const [loading, setLoading] = useState(true);
  const userName = localStorage.getItem('userName') || 'Kullanıcı';

  const fetchData = async () => {
    setLoading(true);
    try {
      const [r, t] = await Promise.all([api.getRecords(), api.getTasks()]);
      setRecords(Array.isArray(r) ? r : []);
      const enrichedTasks = Array.isArray(t) ? t.map(task => {
        const record = Array.isArray(r) ? r.find(rec => rec.id === task.record_id) : null;
        return {
          ...task,
          category: task.category || record?.category || 'Diğer',
          file_name: record?.file_name || record?.auto_title || `Kayıt #${task.record_id}`,
        };
      }) : [];
      setTasks(enrichedTasks);
    } catch (e) {
      console.error(e);
    }
    setLoading(false);
  };

  useEffect(() => { fetchData(); }, []);

  const renderView = () => {
    switch (activeTab) {
      case 'home':     return <HomeView records={records} tasks={tasks} loading={loading} onRefresh={fetchData} onNavigate={setActiveTab} />;
      case 'tasks':    return <TasksView tasks={tasks} onToggle={fetchData} onDelete={fetchData} />;
      case 'records':  return <RecordsView records={records} tasks={tasks} onDelete={fetchData} onUpload={fetchData} />;
      case 'calendar': return <CalendarView tasks={tasks} onNavigate={setActiveTab} />;
      case 'chat':     return <ChatView />;
      case 'stats':    return <StatsView records={records} tasks={tasks} />;
      default:         return <HomeView records={records} tasks={tasks} loading={loading} onRefresh={fetchData} onNavigate={setActiveTab} />;
    }
  };

  return (
    <div className="flex h-screen aurora-bg text-white overflow-hidden">
      <Sidebar activeTab={activeTab} onNavigate={setActiveTab} userName={userName} onLogout={onLogout} />
      <main className="flex-1 overflow-y-auto">
        {renderView()}
      </main>
      <div style={{ position: 'fixed', bottom: '32px', right: '32px', zIndex: 999 }}>
        {/* Konuşma balonu */}
        <div style={{
          position: 'absolute',
          bottom: '8px',
          right: '76px',
          background: 'rgba(30, 41, 59, 0.95)',
          border: '1px solid rgba(99, 102, 241, 0.3)',
          borderRadius: '12px 12px 12px 4px',
          padding: '8px 12px',
          whiteSpace: 'nowrap',
          fontSize: '12px',
          fontWeight: '600',
          color: '#c7d2fe',
          boxShadow: '0 4px 20px rgba(99, 102, 241, 0.2)',
          pointerEvents: 'none',
        }}>
          Asistan ile konuşun 💬
          {/* Balon kuyruğu */}
          <div style={{
            position: 'absolute',
            top: '50%',
            right: '-6px',
            transform: 'translateY(-50%) rotate(45deg)',
            width: '12px',
            height: '12px',
            background: 'rgba(30, 41, 59, 0.95)',
            border: '1px solid rgba(99, 102, 241, 0.3)',
            borderBottom: 'none',
            borderLeft: 'none',
          }} />
        </div>

        {/* FAB butonu */}
        <button
          onClick={() => setActiveTab('chat')}
          style={{
            width: '64px',
            height: '64px',
            borderRadius: '50%',
            overflow: 'hidden',
            border: '3px solid rgba(99, 102, 241, 0.5)',
            boxShadow: '0 0 24px rgba(99, 102, 241, 0.4), 0 8px 32px rgba(0,0,0,0.4)',
            cursor: 'pointer',
            padding: 0,
            background: 'transparent',
            transition: 'transform 0.2s, box-shadow 0.2s',
          }}
          onMouseEnter={e => {
            e.currentTarget.style.transform = 'scale(1.1)';
            e.currentTarget.style.boxShadow = '0 0 32px rgba(99, 102, 241, 0.7), 0 8px 32px rgba(0,0,0,0.5)';
          }}
          onMouseLeave={e => {
            e.currentTarget.style.transform = 'scale(1)';
            e.currentTarget.style.boxShadow = '0 0 24px rgba(99, 102, 241, 0.4), 0 8px 32px rgba(0,0,0,0.4)';
          }}
        >
          <img src="/logo.png" alt="asistan" style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} />
        </button>
      </div>
    </div>
  );
}
