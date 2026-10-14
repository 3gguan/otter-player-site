/* Otter Player — language switcher for the static support site.
   No dependencies. Remembers the choice in localStorage. */

(function () {
  'use strict';

  var SUPPORTED = ['zh-Hans', 'zh-Hant', 'en', 'ja'];
  var KEY = 'otter-player-lang';

  function normalise(tag) {
    if (!tag) return null;
    var t = String(tag);
    if (/^zh\b/i.test(t)) {
      return /hant|tw|hk|mo/i.test(t) ? 'zh-Hant' : 'zh-Hans';
    }
    if (/^ja\b/i.test(t)) return 'ja';
    if (/^en\b/i.test(t)) return 'en';
    return null;
  }

  function detect() {
    var saved = null;
    try { saved = localStorage.getItem(KEY); } catch (e) { /* private mode */ }
    if (SUPPORTED.indexOf(saved) !== -1) return saved;

    var list = navigator.languages || [navigator.language || 'en'];
    for (var i = 0; i < list.length; i++) {
      var hit = normalise(list[i]);
      if (hit) return hit;
    }
    return 'en';
  }

  function apply(lang) {
    document.documentElement.setAttribute('data-lang', lang);
    document.documentElement.setAttribute('lang', lang);

    var buttons = document.querySelectorAll('[data-set-lang]');
    for (var i = 0; i < buttons.length; i++) {
      var on = buttons[i].getAttribute('data-set-lang') === lang;
      buttons[i].setAttribute('aria-pressed', on ? 'true' : 'false');
    }
  }

  function set(lang) {
    apply(lang);
    try { localStorage.setItem(KEY, lang); } catch (e) { /* ignore */ }
  }

  document.addEventListener('click', function (ev) {
    var el = ev.target.closest ? ev.target.closest('[data-set-lang]') : null;
    if (el) {
      ev.preventDefault();
      set(el.getAttribute('data-set-lang'));
    }
  });

  apply(detect());
})();
