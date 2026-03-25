(function(){
  function el(html){
    const t = document.createElement('template');
    t.innerHTML = html.trim();
    return t.content.firstChild;
  }

  function showToast(title, body, kind){
    const container = document.getElementById('toastContainer');
    if(!container) return;
    const id = 't' + Math.random().toString(16).slice(2);
    const node = el(`<div id="${id}" class="toast" role="alert" aria-live="assertive" aria-atomic="true">
      <div class="toast-header">
        <strong class="me-auto">${title}</strong>
        <small class="text-muted">الآن</small>
        <button type="button" class="btn-close" data-bs-dismiss="toast" aria-label="إغلاق"></button>
      </div>
      <div class="toast-body">${body}</div>
    </div>`);
    container.appendChild(node);
    const toast = new bootstrap.Toast(node, { delay: 4000 });
    toast.show();
    node.addEventListener('hidden.bs.toast', ()=> node.remove());
  }

  function bumpBadge(id){
    const b = document.getElementById(id);
    if(!b) return;
    const n = parseInt(b.textContent || '0', 10) || 0;
    b.textContent = String(n + 1);
    b.style.display = '';
  }

  // Connect SignalR only for logged-in admin pages
  if (window.signalR && document.getElementById('sidebar')) {
    const conn = new signalR.HubConnectionBuilder()
      .withUrl('/hubs/notify')
      .withAutomaticReconnect()
      .build();

    // Generic notifications (persisted + may be pushed via FCM)
    conn.on('notification', (p)=>{
      const title = (p && (p.title || p.Title)) ? (p.title || p.Title) : 'إشعار';
      const body = (p && (p.body || p.Body)) ? (p.body || p.Body) : '';
      showToast(title, body, 'info');
      bumpBadge('badgeNotifications');
    });

    conn.on('order_new', (p)=>{ showToast('طلب جديد', `طلب رقم #${p.id ?? p.orderId ?? p.Id ?? ''}`, 'info'); bumpBadge('badgeOrders'); });
    conn.on('complaint_new', (p)=>{ showToast('رسالة/شكوى جديدة', `محادثة #${p.id ?? p.threadId ?? ''}`, 'warn'); bumpBadge('badgeChats'); });
    conn.off('chat_message_received');
    conn.on('chat_message_received', (p)=>{ showToast('رسالة جديدة', `محادثة #${p.threadId}`, 'warn'); bumpBadge('badgeChats'); });
    conn.on('driver_changed', (p)=>{ bumpBadge('badgeDrivers'); });
    conn.on('order_status', (p)=>{ showToast('تحديث حالة طلب', `طلب #${p.orderId} -> ${p.status}`, 'info'); });
    conn.on('order_eta', (p)=>{ showToast('تحديث وقت الوصول', `طلب #${p.orderId} تم تحديث الوقت المتوقع`, 'info'); });
    conn.on('order_edited', (p)=>{
      const id = p?.orderId ?? p?.id ?? '';
      const cust = p?.customerName ? ` (${p.customerName})` : '';
      showToast('تم تعديل الطلب من قبل الزبون', `طلب #${id}${cust}`, 'warn');
      bumpBadge('badgeOrders');
    });

    conn.start().catch(()=>{});
  }

  // Branding (RestaurantName + Logo) for all admin pages
  async function loadBranding(){
    const nameEl = document.getElementById('brandName');
    const logoEl = document.getElementById('brandLogo');
    const subtitleEl = document.getElementById('brandSubtitle');
    try{
      const res = await fetch('/api/public/app-config', { credentials: 'same-origin' });
      if(!res.ok) return;
      const s = await res.json();
      const name = (s.restaurantName || '').toString().trim();
      const rawLogo = (s.logoUrl || '').toString().trim();
      // Cache-bust logo so admin sees the new one immediately after saving.
      const v = (s.settingsVersion || s.updatedAtUtc || Date.now()).toString();
      const logo = rawLogo ? (rawLogo + (rawLogo.includes('?') ? '&' : '?') + 'v=' + encodeURIComponent(v)) : '';
      if(nameEl) nameEl.textContent = name || 'لوحة التحكم';
      document.title = (name ? `${name} — لوحة التحكم` : 'لوحة التحكم');
      const pt = document.getElementById('pageTitle');
      if(pt) pt.textContent = document.title;
      if(logoEl){
        if(logo){ logoEl.src = logo; logoEl.style.display = ''; }
        else { logoEl.style.display = 'none'; }
      }
      if(subtitleEl && name){ subtitleEl.textContent = ''; }
    }catch(_){ }
  }

  if (document.getElementById('sidebar')) {
    // Only on authenticated layout
    loadBranding();
  }

  // Expose for Settings page to refresh branding instantly after save.
  window.reloadBranding = loadBranding;

  window.adminToast = showToast;
})();
