(function () {
  'use strict';

  var content = null;
  var hasApi = false;
  var isLoggedIn = false;

  var loginView = document.getElementById('login-view');
  var editorView = document.getElementById('editor-view');
  var loginForm = document.getElementById('login-form');
  var loginError = document.getElementById('login-error');
  var contentForm = document.getElementById('content-form');
  var statusEl = document.getElementById('status');

  function show(el) { el.classList.remove('hidden'); }
  function hide(el) { el.classList.add('hidden'); }

  function status(msg, type) {
    statusEl.textContent = msg;
    statusEl.className = 'status-bar show ' + (type || 'info');
  }

  function api(path, options) {
    return fetch(path, Object.assign({ credentials: 'same-origin' }, options || {}));
  }

  function fieldId(name) {
    return 'f-' + name.replace(/\./g, '-');
  }

  function checkboxField(label, name, checked) {
    var id = fieldId(name);
    return (
      '<div class="field field-check">' +
      '<label for="' + id + '">' +
      '<input type="checkbox" id="' + id + '" data-path="' + name + '" data-type="boolean"' +
      (checked ? ' checked' : '') + '> ' + label +
      '</label></div>'
    );
  }

  function selectField(label, name, value, options) {
    var id = fieldId(name);
    var opts = (options || []).map(function (o) {
      return '<option value="' + escapeAttr(o) + '"' + (value === o ? ' selected' : '') + '>' + escapeHtml(o) + '</option>';
    }).join('');
    return (
      '<div class="field"><label for="' + id + '">' + label + '</label>' +
      '<select id="' + id + '" data-path="' + name + '">' + opts + '</select></div>'
    );
  }

  function field(label, name, value, opts) {
    opts = opts || {};
    var id = fieldId(name);
    var tag = opts.textarea ? 'textarea' : 'input';
    var extra = opts.textarea ? '' : ' type="' + (opts.type || 'text') + '"';
    return (
      '<div class="field">' +
      '<label for="' + id + '">' + label + '</label>' +
      '<' + tag + ' id="' + id + '" name="' + name + '" data-path="' + name + '"' + extra + '>' +
      (opts.textarea ? escapeHtml(value || '') + '</' + tag + '>' : ' value="' + escapeAttr(value || '') + '">') +
      (opts.hint ? '<small>' + opts.hint + '</small>' : '') +
      '</div>'
    );
  }

  function escapeHtml(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  function escapeAttr(s) {
    return String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;');
  }

  function bulletsField(label, name, items) {
    var id = fieldId(name);
    return (
      '<div class="field bullets-editor">' +
      '<label for="' + id + '">' + label + '</label>' +
      '<textarea id="' + id + '" name="' + name + '" data-path="' + name + '" data-type="bullets">' +
      escapeHtml((items || []).join('\n')) +
      '</textarea><small>По одному пункту на строку</small></div>'
    );
  }

  function buildForm(c) {
    var html = '';

    html += '<div class="section-card"><h2>SEO и бренд</h2>';
    html += field('Заголовок вкладки', 'meta.title', c.meta.title);
    html += field('Описание (meta)', 'meta.description', c.meta.description, { textarea: true });
    html += field('Цвет темы (#hex)', 'meta.themeColor', c.meta.themeColor);
    html += field('Название бренда', 'brand.name', c.brand.name);
    html += field('Текст в подвале', 'brand.footerDescription', c.brand.footerDescription, { textarea: true });
    html += field('Копирайт', 'brand.copyright', c.brand.copyright);
    html += '</div>';

    html += '<div class="section-card"><h2>Меню в шапке</h2>';
    (c.nav || []).forEach(function (item, i) {
      html += '<div class="item-block">';
      html += field('Пункт ' + (i + 1) + ' — текст', 'nav.' + i + '.label', item.label);
      html += field('Ссылка', 'nav.' + i + '.href', item.href, { hint: 'Например #pricing или https://...' });
      html += checkboxField('Показать как кнопку', 'nav.' + i + '.button', !!item.button);
      html += '</div>';
    });
    html += '</div>';

    html += '<div class="section-card"><h2>Главный экран</h2>';
    html += field('Бейдж', 'hero.badge', c.hero.badge);
    html += field('Заголовок', 'hero.title', c.hero.title);
    html += field('Подзаголовок', 'hero.lead', c.hero.lead, { textarea: true });
    (c.hero.actions || []).forEach(function (a, i) {
      html += '<div class="item-block">';
      html += field('Кнопка ' + (i + 1) + ' — текст', 'hero.actions.' + i + '.label', a.label);
      html += field('Ссылка', 'hero.actions.' + i + '.href', a.href);
      html += selectField('Стиль', 'hero.actions.' + i + '.style', a.style || 'primary', ['primary', 'outline']);
      html += '</div>';
    });
    (c.hero.stats || []).forEach(function (s, i) {
      html += field('Стат ' + (i + 1) + ' — значение', 'hero.stats.' + i + '.value', s.value);
      html += field('Стат ' + (i + 1) + ' — подпись', 'hero.stats.' + i + '.label', s.label);
    });
    var preview = (c.hero && c.hero.preview) || { header: '', sensors: [] };
    html += field('Превью — заголовок', 'hero.preview.header', preview.header);
    (preview.sensors || []).forEach(function (s, i) {
      html += '<div class="item-block">';
      html += field('Датчик ' + (i + 1), 'hero.preview.sensors.' + i + '.label', s.label);
      html += field('Значение', 'hero.preview.sensors.' + i + '.value', s.value);
      html += field('Статус', 'hero.preview.sensors.' + i + '.status', s.status);
      html += field('Класс (ok/warn)', 'hero.preview.sensors.' + i + '.state', s.state);
      html += '</div>';
    });
    html += '</div>';

    html += '<div class="section-card"><h2>Возможности</h2>';
    html += field('Заголовок', 'features.title', c.features.title);
    html += field('Подзаголовок', 'features.subtitle', c.features.subtitle, { textarea: true });
    (c.features.items || []).forEach(function (f, i) {
      html += '<div class="item-block">';
      html += field('Иконка (emoji)', 'features.items.' + i + '.icon', f.icon);
      html += field('Заголовок', 'features.items.' + i + '.title', f.title);
      html += field('Текст', 'features.items.' + i + '.text', f.text, { textarea: true });
      html += '</div>';
    });
    html += '</div>';

    html += '<div class="section-card"><h2>Режимы</h2>';
    html += field('Заголовок', 'modes.title', c.modes.title);
    html += field('Подзаголовок', 'modes.subtitle', c.modes.subtitle, { textarea: true });
    (c.modes.items || []).forEach(function (m, i) {
      html += '<div class="item-block">';
      html += field('Название', 'modes.items.' + i + '.title', m.title);
      html += field('Подзаголовок', 'modes.items.' + i + '.subtitle', m.subtitle);
      html += field('Тег (MVP-B и т.д.)', 'modes.items.' + i + '.tag', m.tag);
      html += checkboxField('Выделить карточку (featured)', 'modes.items.' + i + '.featured', !!m.featured);
      html += bulletsField('Пункты списка', 'modes.items.' + i + '.bullets', m.bullets);
      html += '</div>';
    });
    html += '</div>';

    html += '<div class="section-card"><h2>Как работает</h2>';
    html += field('Заголовок', 'how.title', c.how.title);
    html += field('Подзаголовок', 'how.subtitle', c.how.subtitle, { textarea: true });
    (c.how.steps || []).forEach(function (step, i) {
      html += '<div class="item-block">';
      html += field('Шаг ' + (i + 1), 'how.steps.' + i + '.title', step.title);
      html += field('Описание', 'how.steps.' + i + '.text', step.text, { textarea: true });
      html += '</div>';
    });
    html += '</div>';

    html += '<div class="section-card"><h2>Тарифы</h2>';
    html += field('Заголовок', 'pricing.title', c.pricing.title);
    html += field('Подзаголовок', 'pricing.subtitle', c.pricing.subtitle, { textarea: true });
    (c.pricing.plans || []).forEach(function (p, i) {
      html += '<div class="item-block">';
      html += field('Название', 'pricing.plans.' + i + '.name', p.name);
      html += field('Цена', 'pricing.plans.' + i + '.price', p.price);
      html += field('Примечание к цене', 'pricing.plans.' + i + '.priceNote', p.priceNote || '');
      html += checkboxField('Пометить как популярный', 'pricing.plans.' + i + '.popular', !!p.popular);
      html += bulletsField('Что входит', 'pricing.plans.' + i + '.bullets', p.bullets);
      html += '</div>';
    });
    html += '</div>';

    html += '<div class="section-card"><h2>Разработчикам</h2>';
    html += field('Заголовок', 'developers.title', c.developers.title);
    html += field('Подзаголовок', 'developers.subtitle', c.developers.subtitle, { textarea: true });
    html += bulletsField('Теги стека (по строке)', 'developers.stack', c.developers.stack);
    html += field('Текст про статусы', 'developers.statusNote', c.developers.statusNote, { textarea: true });
    html += field('Текст про репозиторий', 'developers.repoNote', c.developers.repoNote, { textarea: true });
    html += bulletsField('Список материалов', 'developers.repoItems', c.developers.repoItems);
    html += '</div>';

    html += '<div class="section-card"><h2>Подвал сайта</h2>';
    (c.footer.productLinks || []).forEach(function (link, i) {
      html += '<div class="item-block">';
      html += field('Ссылка ' + (i + 1) + ' — текст', 'footer.productLinks.' + i + '.label', link.label);
      html += field('URL', 'footer.productLinks.' + i + '.href', link.href);
      html += '</div>';
    });
    html += bulletsField('Документы (текстом)', 'footer.docItems', c.footer.docItems);
    html += '</div>';

    html += '<div class="section-card"><h2>Контакты</h2>';
    html += field('Заголовок', 'contact.title', c.contact.title);
    html += field('Текст', 'contact.text', c.contact.text, { textarea: true });
    html += field('Email', 'contact.email', c.contact.email, { type: 'email' });
    html += field('Кнопка', 'contact.buttonLabel', c.contact.buttonLabel);
    html += '</div>';

    return html;
  }

  function setByPath(obj, path, value) {
    var parts = path.split('.');
    var cur = obj;
    for (var i = 0; i < parts.length - 1; i++) {
      var key = parts[i];
      if (/^\d+$/.test(key)) key = parseInt(key, 10);
      if (cur[key] == null) cur[key] = /^\d+$/.test(parts[i + 1]) ? [] : {};
      cur = cur[key];
    }
    var last = parts[parts.length - 1];
    if (/^\d+$/.test(last)) last = parseInt(last, 10);
    cur[last] = value;
  }

  function collectForm() {
    var data = JSON.parse(JSON.stringify(content));
    contentForm.querySelectorAll('[data-path]').forEach(function (el) {
      var path = el.getAttribute('data-path');
      var type = el.getAttribute('data-type');
      var val;
      if (type === 'boolean') {
        val = el.checked;
      } else if (type === 'bullets') {
        val = el.value.split('\n').map(function (s) { return s.trim(); }).filter(Boolean);
      } else {
        val = el.value;
      }
      setByPath(data, path, val);
    });
    return data;
  }

  function loadContent() {
    return api('/api/content')
      .then(function (r) {
        var ct = r.headers.get('content-type') || '';
        if (r.ok && ct.indexOf('application/json') !== -1) {
          hasApi = true;
          return r.json();
        }
        return fetch('../data/content.json').then(function (r2) {
          if (!r2.ok) throw new Error('Не найден content.json');
          return r2.json();
        });
      });
  }

  function checkSession() {
    return api('/api/admin/me')
      .then(function (r) {
        if (!r.ok) return false;
        return r.json().then(function (d) { return !!d.ok; });
      })
      .catch(function () { return false; });
  }

  function showEditor() {
    hide(loginView);
    show(editorView);
    contentForm.innerHTML = buildForm(content);
    if (!hasApi) {
      status('Работает режим без сервера: сохранение только через «Скачать JSON».', 'info');
    }
  }

  function showLogin() {
    show(loginView);
    hide(editorView);
  }

  function init() {
    loadContent()
      .then(function (data) {
        content = data;
        return checkSession();
      })
      .then(function (loggedIn) {
        isLoggedIn = loggedIn;
        if (!hasApi || loggedIn) {
          showEditor();
        } else {
          showLogin();
        }
      })
      .catch(function (err) {
        showLogin();
        loginError.textContent = 'Ошибка: ' + err.message;
        show(loginError);
      });
  }

  loginForm.addEventListener('submit', function (e) {
    e.preventDefault();
    hide(loginError);
    var password = document.getElementById('password').value;

    if (!hasApi) {
      status('Для входа без сервера откройте админку через npm start в website/server', 'info');
      showEditor();
      return;
    }

    api('/api/admin/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ password: password })
    })
      .then(function (r) { return r.json().then(function (d) { return { ok: r.ok, data: d }; }); })
      .then(function (res) {
        if (!res.ok) {
          loginError.textContent = res.data.error || 'Неверный пароль';
          show(loginError);
          return;
        }
        isLoggedIn = true;
        document.getElementById('password').value = '';
        showEditor();
        status('Вход выполнен', 'ok');
      })
      .catch(function () {
        loginError.textContent = 'Ошибка соединения с сервером';
        show(loginError);
      });
  });

  document.getElementById('btn-save').addEventListener('click', function () {
    var data = collectForm();
    if (!hasApi || !isLoggedIn) {
      downloadJson(data);
      status('Файл скачан. Замените website/data/content.json и обновите хостинг.', 'ok');
      return;
    }
    api('/api/admin/content', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data)
    })
      .then(function (r) { return r.json().then(function (d) { return { ok: r.ok, data: d }; }); })
      .then(function (res) {
        if (!res.ok) {
          status(res.data.error || 'Ошибка сохранения', 'err');
          if (res.data.error === 'Unauthorized') showLogin();
          return;
        }
        content = data;
        status('Сохранено на сервере', 'ok');
      })
      .catch(function () { status('Ошибка сети', 'err'); });
  });

  document.getElementById('btn-download').addEventListener('click', function () {
    downloadJson(collectForm());
    status('content.json скачан', 'ok');
  });

  document.getElementById('btn-logout').addEventListener('click', function () {
    if (hasApi && isLoggedIn) {
      api('/api/admin/logout', { method: 'POST' }).finally(function () {
        isLoggedIn = false;
        showLogin();
      });
    } else {
      showLogin();
    }
  });

  function downloadJson(data) {
    var blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
    var a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = 'content.json';
    a.click();
    URL.revokeObjectURL(a.href);
  }

  init();
})();
