// Vieira-STRIKE Web Portal & Admin Panel
// Conecta-se à API RESTful FastAPI do servidor

const App = {
  apiBase: localStorage.getItem('vs_api_url') || 'http://localhost:8000',
  token: localStorage.getItem('vs_jwt_token') || null,
  user: null,
  roles: [],

  init() {
    this.setupNavigation();
    this.setupSettings();
    this.checkAuth();
    this.loadCatalog();
  },

  // Toast Notifications
  toast(msg, type = 'info') {
    const container = document.getElementById('toast-container');
    const el = document.createElement('div');
    el.className = `toast ${type}`;
    el.textContent = msg;
    container.appendChild(el);
    setTimeout(() => el.remove(), 4000);
  },

  // API Fetch Helper
  async api(endpoint, options = {}) {
    const headers = {
      'Content-Type': 'application/json',
      ...(options.headers || {})
    };
    if (this.token) {
      headers['Authorization'] = `Bearer ${this.token}`;
    }

    try {
      const res = await fetch(`${this.apiBase}${endpoint}`, {
        ...options,
        headers
      });

      if (res.status === 401 && this.token) {
        this.logout();
        this.toast('Sessão expirada. Faça login novamente.', 'error');
        throw new Error('Sessão expirada');
      }

      const data = await res.json().catch(() => null);
      if (!res.ok) {
        const errorDetail = data && (data.detail || data.message) ? data.detail : `Erro HTTP ${res.status}`;
        throw new Error(errorDetail);
      }
      return data;
    } catch (err) {
      console.error(`[API Error] ${endpoint}:`, err);
      throw err;
    }
  },

  // Navigation
  setupNavigation() {
    const links = document.querySelectorAll('.nav-link[data-tab]');
    links.forEach(link => {
      link.addEventListener('click', (e) => {
        e.preventDefault();
        const tab = link.getAttribute('data-tab');
        this.showTab(tab);
      });
    });
  },

  showTab(tabId) {
    document.querySelectorAll('.nav-link').forEach(l => l.classList.remove('active'));
    document.querySelectorAll('.tab-pane').forEach(p => p.classList.remove('active'));

    const targetLink = document.querySelector(`.nav-link[data-tab="${tabId}"]`);
    const targetPane = document.getElementById(`tab-${tabId}`);

    if (targetLink) targetLink.classList.add('active');
    if (targetPane) targetPane.classList.add('active');

    // Trigger loads based on tab
    if (tabId === 'profile') this.loadProfile();
    if (tabId === 'shop') this.loadCatalog();
    if (tabId === 'wallet') this.loadWallet();
    if (tabId === 'admin') this.loadAdminDashboard();
  },

  // Settings: API URL
  setupSettings() {
    const input = document.getElementById('setting-api-url');
    if (input) {
      input.value = this.apiBase;
      input.addEventListener('change', () => {
        let val = input.value.trim().replace(/\/+$/, '');
        if (!val) val = 'http://localhost:8000';
        this.apiBase = val;
        localStorage.setItem('vs_api_url', val);
        this.toast(`URL da API salva: ${val}`, 'success');
      });
    }
  },

  // Auth
  async checkAuth() {
    if (!this.token) {
      this.updateAuthUI(false);
      return;
    }

    try {
      // Decode JWT payload for roles
      const payloadBase64 = this.token.split('.')[1];
      const payload = JSON.parse(atob(payloadBase64));
      this.roles = payload.roles || [];

      // Fetch user profile
      this.user = await this.api('/api/players/me');
      this.updateAuthUI(true);
    } catch (err) {
      this.logout();
    }
  },

  updateAuthUI(isLoggedIn) {
    const guestBox = document.getElementById('auth-guest');
    const userBox = document.getElementById('auth-user');
    const adminLink = document.querySelector('.nav-link[data-tab="admin"]');

    if (isLoggedIn && this.user) {
      guestBox.style.display = 'none';
      userBox.style.display = 'flex';
      document.getElementById('nav-user-name').textContent = this.user.display_name;
      document.getElementById('nav-user-rank').textContent = this.user.rank;

      const hasAdmin = this.roles.some(r => ['administrator', 'owner', 'moderator'].includes(r));
      if (adminLink) adminLink.style.display = hasAdmin ? 'inline-block' : 'none';
    } else {
      guestBox.style.display = 'flex';
      userBox.style.display = 'none';
      if (adminLink) adminLink.style.display = 'none';
    }
  },

  async login(username, password) {
    try {
      const form = new URLSearchParams();
      form.append('username', username);
      form.append('password', password);

      const res = await fetch(`${this.apiBase}/api/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: form
      });

      const data = await res.json();
      if (!res.ok) throw new Error(data.detail || 'Falha no login');

      this.token = data.access_token;
      localStorage.setItem('vs_jwt_token', this.token);
      this.toast('Login realizado com sucesso!', 'success');
      this.closeModal('modal-login');
      await this.checkAuth();
      this.showTab('profile');
    } catch (err) {
      this.toast(err.message, 'error');
    }
  },

  logout() {
    this.token = null;
    this.user = null;
    this.roles = [];
    localStorage.removeItem('vs_jwt_token');
    this.updateAuthUI(false);
    this.showTab('home');
    this.toast('Você saiu da conta.', 'info');
  },

  // Perfil & Vinculação
  async loadProfile() {
    if (!this.user) {
      this.showTab('home');
      this.openModal('modal-login');
      return;
    }

    try {
      const p = await this.api('/api/players/me');
      this.user = p;
      document.getElementById('prof-name').textContent = p.display_name;
      document.getElementById('prof-level').textContent = p.level;
      document.getElementById('prof-xp').textContent = p.xp.toLocaleString();
      document.getElementById('prof-rank').textContent = p.rank;

      const statusEl = document.getElementById('prof-status');
      statusEl.className = `badge badge-${p.status}`;
      statusEl.textContent = p.status.toUpperCase();

      // Carteira
      const w = await this.api('/api/wallet/me');
      document.getElementById('prof-balance').textContent = (w.balance / 100).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
    } catch (err) {
      this.toast('Erro ao atualizar perfil', 'error');
    }
  },

  async generateLinkCode() {
    try {
      const res = await this.api('/api/players/me/link-code', { method: 'POST' });
      document.getElementById('link-code-val').textContent = res.code;
      document.getElementById('link-code-area').style.display = 'block';
      this.toast('Código gerado! Digite no console do CS: /vincular ' + res.code, 'success');
    } catch (err) {
      this.toast(err.message, 'error');
    }
  },

  // Loja & Catálogo
  async loadCatalog() {
    const grid = document.getElementById('shop-items-grid');
    if (!grid) return;
    grid.innerHTML = '<p class="text-muted">Carregando catálogo...</p>';

    try {
      const items = await this.api('/api/items/');
      if (items.length === 0) {
        grid.innerHTML = '<p class="text-muted">Nenhum item disponível no momento.</p>';
        return;
      }

      grid.innerHTML = items.map(item => `
        <div class="card">
          <div class="card-header">
            <span class="badge ${item.item_type === 'weapon_skin' ? 'badge-linked' : 'badge-verified'}">
              ${item.item_type === 'weapon_skin' ? 'Skin de Arma' : 'Modelo de Jogador'}
            </span>
            <span class="badge badge-rank">v${item.asset_version}</span>
          </div>
          <h3 class="card-title">${item.display_name}</h3>
          <p style="color: var(--text-muted); font-size: 0.8rem; margin: 0.3rem 0 1rem; font-family: monospace;">
            SKU: ${item.sku}
          </p>
          <div style="display: flex; justify-content: space-between; align-items: center; margin-top: auto;">
            <span style="font-size: 1.25rem; font-weight: 800; color: var(--accent);">
              ${(item.price / 100).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })}
            </span>
            <button class="btn btn-primary btn-sm" onclick="App.toast('Para comprar, acesse o servidor CS e digite /loja', 'info')">
              Comprar no CS
            </button>
          </div>
        </div>
      `).join('');
    } catch (err) {
      grid.innerHTML = '<p style="color: var(--accent-red);">Falha ao conectar à API da Loja.</p>';
    }
  },

  // Carteira & Extrato
  async loadWallet() {
    if (!this.user) {
      this.openModal('modal-login');
      return;
    }

    try {
      const w = await this.api('/api/wallet/me');
      document.getElementById('wallet-current-bal').textContent =
        (w.balance / 100).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });

      const txs = await this.api('/api/wallet/me/transactions');
      const tbody = document.getElementById('wallet-tx-tbody');
      if (txs.length === 0) {
        tbody.innerHTML = '<tr><td colspan="4" style="text-align:center; color: var(--text-muted);">Nenhuma movimentação registrada.</td></tr>';
        return;
      }

      tbody.innerHTML = txs.map(t => {
        const isPositive = t.amount > 0;
        const formattedAmount = (Math.abs(t.amount) / 100).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
        const date = new Date(t.created_at).toLocaleString('pt-BR');
        return `
          <tr>
            <td><code>${t.type.toUpperCase()}</code></td>
            <td style="color: ${isPositive ? 'var(--accent-green)' : 'var(--accent-red)'}; font-weight: 700;">
              ${isPositive ? '+' : '-'} ${formattedAmount}
            </td>
            <td>${t.currency}</td>
            <td style="color: var(--text-muted); font-size: 0.8rem;">${date}</td>
          </tr>
        `;
      }).join('');
    } catch (err) {
      this.toast('Erro ao carregar carteira', 'error');
    }
  },

  // Recargas PIX
  async createPixOrder(amountCents) {
    try {
      const order = await this.api('/api/payments/orders', {
        method: 'POST',
        body: JSON.stringify({ amount: amountCents, provider: 'pix' })
      });

      document.getElementById('pix-order-id').textContent = order.id;
      document.getElementById('pix-order-amount').textContent =
        (order.amount / 100).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
      document.getElementById('pix-modal-content').style.display = 'block';
      this.toast('Pedido PIX gerado! Aguardando confirmação do webhook.', 'info');
    } catch (err) {
      this.toast(err.message, 'error');
    }
  },

  // Painel Administrativo
  async loadAdminDashboard() {
    try {
      const stats = await this.api('/api/admin/stats');
      document.getElementById('admin-stat-players').textContent = stats.total_players;
      document.getElementById('admin-stat-items').textContent = stats.total_items;
      document.getElementById('admin-stat-orders').textContent = stats.total_orders;
      document.getElementById('admin-stat-revenue').textContent =
        (stats.total_revenue_cents / 100).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });

      // Carregar Logs de Auditoria
      const logs = await this.api('/api/admin/audit-logs');
      const tbody = document.getElementById('admin-audit-tbody');
      tbody.innerHTML = logs.map(l => `
        <tr>
          <td><code>${l.action}</code></td>
          <td>${l.target_type || '-'}</td>
          <td style="font-family: monospace; font-size: 0.75rem;">${l.target_id || '-'}</td>
          <td style="color: var(--text-muted); font-size: 0.8rem;">${new Date(l.created_at).toLocaleString('pt-BR')}</td>
        </tr>
      `).join('');
    } catch (err) {
      this.toast('Acesso negado ou erro ao carregar métricas administrativas.', 'error');
    }
  },

  async adjustBalanceSubmit(e) {
    e.preventDefault();
    const playerId = document.getElementById('adj-player-id').value.trim();
    const amountReal = parseFloat(document.getElementById('adj-amount').value);
    const reason = document.getElementById('adj-reason').value.trim();

    if (!playerId || isNaN(amountReal) || !reason) {
      this.toast('Preencha todos os campos obrigatórios', 'error');
      return;
    }

    const amountCents = Math.round(amountReal * 100);
    try {
      await this.api('/api/wallet/adjust', {
        method: 'POST',
        body: JSON.stringify({ player_id: playerId, amount: amountCents, reason })
      });
      this.toast('Ajuste de saldo efetuado e registrado em auditoria!', 'success');
      this.closeModal('modal-adjust-balance');
      this.loadAdminDashboard();
    } catch (err) {
      this.toast(err.message, 'error');
    }
  },

  // Modal helpers
  openModal(id) {
    const el = document.getElementById(id);
    if (el) el.classList.add('open');
  },

  closeModal(id) {
    const el = document.getElementById(id);
    if (el) el.classList.remove('open');
  }
};

document.addEventListener('DOMContentLoaded', () => App.init());
