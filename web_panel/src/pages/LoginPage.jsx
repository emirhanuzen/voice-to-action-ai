import { useState } from 'react';
import api from '../api';

export default function LoginPage({ onLogin }) {
  const [isRegister, setIsRegister] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [fullName, setFullName] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleLogin = async () => {
    setLoading(true); setError('');
    try {
      const data = await api.login(email, password);
      if (data.access_token) {
        localStorage.setItem('userEmail', email);
        onLogin(data.access_token, data.full_name);
      } else {
        setError(data.detail || 'Giriş başarısız');
      }
    } catch {
      setError('Sunucuya bağlanılamadı');
    }
    setLoading(false);
  };

  const handleRegister = async () => {
    setLoading(true); setError('');
    try {
      const reg = await api.register(fullName, email, password);
      if (reg.id) {
        const data = await api.login(email, password);
        if (data.access_token) onLogin(data.access_token, data.full_name);
      } else {
        setError(reg.detail || 'Kayıt başarısız');
      }
    } catch {
      setError('Sunucuya bağlanılamadı');
    }
    setLoading(false);
  };

  return (
    <div className="min-h-screen aurora-bg flex items-center justify-center p-4">
      {/* Dekoratif daireler */}
      <div className="absolute top-0 right-0 w-96 h-96 bg-blue-500 opacity-10 rounded-full blur-3xl" />
      <div className="absolute bottom-0 left-0 w-80 h-80 bg-indigo-500 opacity-10 rounded-full blur-3xl" />

      <div className="w-full max-w-md relative">
        {/* Logo */}
        <div className="text-center mb-8">
          <div className="w-20 h-20 rounded-full overflow-hidden mx-auto mb-4 shadow-lg shadow-blue-500/30">
            <img src="/logo.png" alt="logo" className="w-full h-full object-cover float-anim" />
          </div>
          <h1 className="text-3xl font-extrabold text-white">VoiceToAction</h1>
          <p className="text-slate-400 mt-1 text-sm">Ses kayıtlarını aksiyona dönüştür</p>
        </div>

        {/* Kart */}
        <div className="glass rounded-3xl p-8 shadow-2xl">
          <h2 className="text-xl font-bold text-white mb-1">
            {isRegister ? 'Hesap Oluştur' : 'Giriş Yap'}
          </h2>
          <p className="text-slate-400 text-sm mb-6">
            {isRegister ? 'Yeni bir hesap oluşturun' : 'Hesabınıza hoş geldiniz 👋'}
          </p>

          <div className="space-y-4">
            {isRegister && (
              <div>
                <label className="text-xs font-semibold text-slate-400 uppercase tracking-wider">Ad Soyad</label>
                <input
                  value={fullName}
                  onChange={e => setFullName(e.target.value)}
                  className="w-full mt-1 px-4 py-3 bg-slate-800 border border-slate-700 rounded-xl text-white placeholder-slate-500 focus:outline-none focus:border-blue-500 transition"
                  placeholder="Emirhan Uzen"
                />
              </div>
            )}
            <div>
              <label className="text-xs font-semibold text-slate-400 uppercase tracking-wider">E-posta</label>
              <input
                type="email"
                value={email}
                onChange={e => setEmail(e.target.value)}
                onKeyDown={e => e.key === 'Enter' && (isRegister ? handleRegister() : handleLogin())}
                className="w-full mt-1 px-4 py-3 bg-slate-800 border border-slate-700 rounded-xl text-white placeholder-slate-500 focus:outline-none focus:border-blue-500 transition"
                placeholder="ornek@email.com"
              />
            </div>
            <div>
              <label className="text-xs font-semibold text-slate-400 uppercase tracking-wider">Şifre</label>
              <input
                type="password"
                value={password}
                onChange={e => setPassword(e.target.value)}
                onKeyDown={e => e.key === 'Enter' && (isRegister ? handleRegister() : handleLogin())}
                className="w-full mt-1 px-4 py-3 bg-slate-800 border border-slate-700 rounded-xl text-white placeholder-slate-500 focus:outline-none focus:border-blue-500 transition"
                placeholder="••••••••"
              />
            </div>
          </div>

          {error && (
            <div className="mt-4 p-3 bg-red-500/10 border border-red-500/20 rounded-xl text-red-400 text-sm">
              {error}
            </div>
          )}

          <button
            onClick={isRegister ? handleRegister : handleLogin}
            disabled={loading}
            className="w-full mt-6 py-3 bg-gradient-to-r from-blue-500 to-indigo-600 text-white font-bold rounded-xl shadow-lg shadow-blue-500/30 hover:shadow-blue-500/50 hover:shadow-[0_0_30px_rgba(59,130,246,0.4)] transition disabled:opacity-50"
          >
            {loading ? 'Yükleniyor...' : (isRegister ? 'Kayıt Ol' : 'Giriş Yap')}
          </button>

          <p className="text-center text-slate-400 text-sm mt-4">
            {isRegister ? 'Zaten hesabınız var mı?' : 'Hesabınız yok mu?'}
            <button
              onClick={() => { setIsRegister(!isRegister); setError(''); }}
              className="text-blue-400 font-semibold ml-1 hover:underline"
            >
              {isRegister ? 'Giriş Yap' : 'Kayıt Ol'}
            </button>
          </p>
        </div>
      </div>
    </div>
  );
}
