import { useState, useEffect } from 'react';
import LoginPage from './pages/LoginPage';
import Dashboard from './pages/Dashboard';

function App() {
  const [isLoggedIn, setIsLoggedIn] = useState(false);

  useEffect(() => {
    const token = localStorage.getItem('token');
    if (token) setIsLoggedIn(true);
  }, []);

  const handleLogin = (token, name) => {
    localStorage.setItem('token', token);
    localStorage.setItem('userName', name);
    setIsLoggedIn(true);
  };

  const handleLogout = () => {
    localStorage.removeItem('token');
    localStorage.removeItem('userName');
    setIsLoggedIn(false);
  };

  return isLoggedIn
    ? <Dashboard onLogout={handleLogout} />
    : <LoginPage onLogin={handleLogin} />;
}

export default App;
