/* Shared authentication gate for multiplayer RPS. Guest tokens are never accepted as identity. */
(function () {
  'use strict';

  const siteKey = window.RPS_TURNSTILE_SITE_KEY || document.querySelector('meta[name="rps-turnstile-site-key"]')?.content || '0x4AAAAAAFFMkP2iICgYR6Yh';
  let pending = null;
  let captchaToken = '';
  let widgetId = null;
  const referralStorageKey = 'rps_pending_referral';

  function pendingReferralCode() {
    try {
      const fromUrl = new URLSearchParams(window.location.search).get('ref');
      const candidate = String(fromUrl || localStorage.getItem(referralStorageKey) || '').trim().toUpperCase();
      if (/^[A-F0-9]{16}$/.test(candidate)) {
        localStorage.setItem(referralStorageKey, candidate);
        return candidate;
      }
    } catch (error) {}
    return '';
  }

  function clearPendingReferralCode() {
    try { localStorage.removeItem(referralStorageKey); } catch (error) {}
  }

  function authRedirectTo() {
    const target = new URL('/games/rps-play.html', window.location.origin);
    const code = pendingReferralCode();
    if (code) target.searchParams.set('ref', code);
    return target.toString();
  }

  function ensureDialog() {
    let dialog = document.getElementById('rpsAuthDialog');
    if (dialog) return dialog;
    dialog = document.createElement('dialog');
    dialog.id = 'rpsAuthDialog';
    dialog.style.cssText = 'width:min(430px,calc(100vw - 28px));border:1px solid #39445d;border-radius:18px;background:#171c27;color:#f8fafc;padding:22px;box-shadow:0 24px 90px #000a';
    dialog.innerHTML = `
      <form id="rpsAuthForm" method="dialog" style="display:grid;gap:12px;font:14px system-ui,sans-serif">
        <h2 style="margin:0;font-size:22px">Sign in to play</h2>
        <p style="margin:0;color:#aab3c4">Create a secure account to save a new profile and play multiplayer. Existing guest rankings stay visible but cannot be changed.</p>
        <button type="button" id="rpsAuthGoogle" style="min-height:46px;padding:12px;border:1px solid #58647d;border-radius:10px;background:#fff;color:#202124;font-weight:800">Continue with Google</button>
        <div aria-hidden="true" style="display:flex;align-items:center;gap:10px;color:#8792a7;font-size:12px"><span style="height:1px;flex:1;background:#39445d"></span>or use email<span style="height:1px;flex:1;background:#39445d"></span></div>
        <label>Email<input id="rpsAuthEmail" type="email" autocomplete="email" required style="display:block;width:100%;box-sizing:border-box;margin-top:5px;padding:12px;border-radius:10px;border:1px solid #39445d;background:#0e131c;color:#fff"></label>
        <label>Password<input id="rpsAuthPassword" type="password" autocomplete="current-password" minlength="8" required style="display:block;width:100%;box-sizing:border-box;margin-top:5px;padding:12px;border-radius:10px;border:1px solid #39445d;background:#0e131c;color:#fff"></label>
        <div id="rpsAuthTurnstile"></div>
        <div id="rpsAuthMessage" role="status" aria-live="polite" style="min-height:18px;color:#d5d9e2"></div>
        <div style="display:flex;gap:8px;flex-wrap:wrap">
          <button type="button" id="rpsAuthSignIn" style="flex:1;padding:12px;border:0;border-radius:10px;background:#efbd3b;color:#17120a;font-weight:800">Sign in</button>
          <button type="button" id="rpsAuthSignUp" style="flex:1;padding:12px;border:1px solid #58647d;border-radius:10px;background:#232b3a;color:#fff;font-weight:800">Create account</button>
        </div>
        <button type="button" id="rpsAuthCancel" style="padding:9px;border:0;background:transparent;color:#aab3c4">Cancel</button>
      </form>`;
    document.body.appendChild(dialog);
    dialog.querySelector('#rpsAuthCancel').addEventListener('click', () => finish(null));
    dialog.querySelector('#rpsAuthSignIn').addEventListener('click', () => submitAuth('signin'));
    dialog.querySelector('#rpsAuthSignUp').addEventListener('click', () => submitAuth('signup'));
    dialog.querySelector('#rpsAuthGoogle').addEventListener('click', submitGoogleAuth);
    dialog.addEventListener('cancel', (event) => { event.preventDefault(); finish(null); });
    loadTurnstile();
    return dialog;
  }

  function setAuthMode(mode) {
    const dialog = document.getElementById('rpsAuthDialog');
    if (!dialog) return;
    const title = dialog.querySelector('h2');
    const password = dialog.querySelector('#rpsAuthPassword');
    if (title) title.textContent = mode === 'signup' ? 'Create your account' : 'Sign in to play';
    if (password) password.autocomplete = mode === 'signup' ? 'new-password' : 'current-password';
  }

  function setMessage(text, error) {
    const node = document.getElementById('rpsAuthMessage');
    if (node) { node.textContent = text; node.style.color = error ? '#ff9b9b' : '#b7dfbd'; }
  }

  function loadTurnstile() {
    if (!siteKey || widgetId !== null) return;
    if (!window.turnstile) {
      if (!document.querySelector('script[data-rps-turnstile]')) {
        const script = document.createElement('script');
        script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';
        script.async = true; script.defer = true; script.dataset.rpsTurnstile = 'true';
        script.onload = loadTurnstile;
        document.head.appendChild(script);
      }
      return;
    }
    const mount = document.getElementById('rpsAuthTurnstile');
    if (!mount) return;
    widgetId = window.turnstile.render(mount, {
      sitekey: siteKey,
      callback: token => { captchaToken = token; },
      'expired-callback': () => { captchaToken = ''; },
      'error-callback': () => { captchaToken = ''; }
    });
  }

  function finish(session) {
    const dialog = document.getElementById('rpsAuthDialog');
    if (dialog?.open) dialog.close();
    if (pending) { const resolve = pending; pending = null; resolve(session || null); }
  }

  async function submitAuth(mode) {
    if (!pending?.db) return;
    const dialog = ensureDialog();
    const email = dialog.querySelector('#rpsAuthEmail').value.trim();
    const password = dialog.querySelector('#rpsAuthPassword').value;
    if (!email || !password) { setMessage('Enter your email and password.', true); return; }
    if (mode === 'signup' && (!siteKey || !captchaToken)) {
      setMessage('Account creation is paused until the configured Turnstile site key and challenge are available. Sign-in remains available.', true);
      return;
    }
    const buttons = dialog.querySelectorAll('button');
    buttons.forEach(button => button.disabled = true);
    try {
      let result;
      if (mode === 'signup') {
        result = await pending.db.auth.signUp({ email, password, options: { captchaToken, emailRedirectTo: authRedirectTo() } });
      } else {
        result = await pending.db.auth.signInWithPassword({ email, password, ...(captchaToken ? { captchaToken } : {}) });
      }
      if (result.error) throw result.error;
      const session = result.data?.session || (await pending.db.auth.getSession()).data?.session;
      if (!session) {
        captchaToken = '';
        if (window.turnstile && widgetId !== null) window.turnstile.reset(widgetId);
        setMessage('Check your email for the confirmation link, then return here and sign in.', false);
        buttons.forEach(button => button.disabled = false);
        return;
      }
      finish(session);
    } catch (error) {
      captchaToken = '';
      if (window.turnstile && widgetId !== null) window.turnstile.reset(widgetId);
      setMessage(error?.message || 'Authentication failed. Try again.', true);
      buttons.forEach(button => button.disabled = false);
    }
  }

  async function submitGoogleAuth() {
    if (!pending?.db) return;
    const button = document.getElementById('rpsAuthGoogle');
    if (button) button.disabled = true;
    try {
      const { error } = await pending.db.auth.signInWithOAuth({
        provider: 'google',
        options: { redirectTo: authRedirectTo() }
      });
      if (error) throw error;
    } catch (error) {
      setMessage(error?.message || 'Google sign-in could not start. Try email and password instead.', true);
      if (button) button.disabled = false;
    }
  }

  function openAuthDialog(db, preferredMode = 'signin') {
    ensureDialog();
    return new Promise(resolve => {
      pending = { db, preferredMode };
      const dialog = document.getElementById('rpsAuthDialog');
      setAuthMode(preferredMode);
      setMessage('', false);
      if (widgetId === null) loadTurnstile();
      if (!dialog.open) dialog.showModal();
      dialog.querySelector(preferredMode === 'signup' ? '#rpsAuthSignUp' : '#rpsAuthSignIn')?.focus();
    });
  }

  async function requireSession(db, preferredMode = 'signin') {
    const { data, error } = await db.auth.getSession();
    if (error) throw error;
    if (data?.session) return data.session;
    return openAuthDialog(db, preferredMode);
  }

  async function getOrCreateProfile(db, username, avatarKey, referralCode = null) {
    const candidate = String(referralCode || pendingReferralCode() || '').trim().toUpperCase();
    const code = /^[A-F0-9]{16}$/.test(candidate) ? candidate : null;
    const session = await requireSession(db);
    if (!session) return null;
    const { data, error } = await db.rpc('rps_v2_get_or_create_profile_with_referral', {
      p_username: String(username || '').trim(),
      p_avatar_key: avatarKey || '🦊',
      p_referral_code: code
    });
    if (error) throw error;
    clearPendingReferralCode();
    localStorage.setItem('rps_username', String(data.username || username || ''));
    return data;
  }

  async function getExistingProfile(db) {
    const session = await requireSession(db);
    if (!session) return null;
    const { data, error } = await db.rpc('rps_v2_get_my_profile');
    if (error) throw error;
    if (data) clearPendingReferralCode();
    return data || null;
  }

  async function signOut(db) {
    const { error } = await db.auth.signOut();
    if (error) throw error;
    ['rps_username', 'rps_avatar', 'rps_player_id', referralStorageKey].forEach(key => localStorage.removeItem(key));
    return true;
  }

  window.RPSAuth = { openAuthDialog, requireSession, getOrCreateProfile, getExistingProfile, signOut };
})();
