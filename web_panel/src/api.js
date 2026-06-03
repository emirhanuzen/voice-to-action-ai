const BASE_URL = 'http://localhost:8000/api';

const authHeaders = () => ({
  'Authorization': `Bearer ${localStorage.getItem('token')}`,
  'Content-Type': 'application/json',
});

export const api = {
  login: (email, password) => {
    const body = new URLSearchParams();
    body.append('username', email);
    body.append('password', password);
    return fetch(`${BASE_URL}/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body,
    }).then(r => r.json());
  },
  register: (fullName, email, password) =>
    fetch(`${BASE_URL}/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ full_name: fullName, email, password }),
    }).then(r => r.json()),
  getRecords: () =>
    fetch(`${BASE_URL}/records`, { headers: authHeaders() }).then(r => r.json()),
  getTasks: () =>
    fetch(`${BASE_URL}/tasks`, { headers: authHeaders() }).then(r => r.json()),
  toggleTask: (id) =>
    fetch(`${BASE_URL}/tasks/${id}/toggle`, {
      method: 'PUT', headers: authHeaders(),
    }).then(r => r.json()),
  deleteTask: (id) =>
    fetch(`${BASE_URL}/tasks/${id}`, {
      method: 'DELETE', headers: authHeaders(),
    }).then(r => r.json()),
  deleteRecord: (id) =>
    fetch(`${BASE_URL}/records/${id}`, {
      method: 'DELETE', headers: authHeaders(),
    }).then(r => r.json()),
  uploadAudio: (file, category) => {
    const formData = new FormData();
    formData.append('file', file);
    formData.append('category', category);
    return fetch(`${BASE_URL}/transcribe`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${localStorage.getItem('token')}` },
      body: formData,
    }).then(r => r.json());
  },
  sendChatMessage: (message) =>
    fetch(`${BASE_URL}/chat`, {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ message }),
    }).then(r => r.json()),
  getUrgentTasks: () =>
    fetch(`${BASE_URL}/tasks/urgent`, { headers: authHeaders() }).then(r => r.json()),
};

export default api;
