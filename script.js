const tabs = [...document.querySelectorAll('.tab')];
const panels = [...document.querySelectorAll('.tab-panel')];
const command = document.querySelector('#typed-command');
const clock = document.querySelector('#clock');
const soundButton = document.querySelector('#sound-toggle');
let audioContext;
let soundOn = false;
const cdnBase = 'https://cdn.jsdelivr.net/gh/davidsmod/the-broken-wiki@main/';
const archiveAudio = new Audio(`${cdnBase}assets/audio/0686_Heartbeat.ogg`);
archiveAudio.loop = true;
archiveAudio.volume = 0.035;

// Keep the landing interface self-contained: official wiki links are redirected
// to the locally generated archive pages while source links inside those pages
// remain available for attribution.
const officialWikiOrigin = 'https://thebrokenscript.wiki.gg/wiki/';
document.querySelectorAll(`a[href^="${officialWikiOrigin}"]`).forEach((link) => {
  const title = decodeURIComponent(link.href.slice(officialWikiOrigin.length));
  const slug = title
    .replace(/_/g, '-')
    .replace(/[^a-zA-Z0-9-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .toLowerCase();
  link.href = `wiki-pages/${slug}.html`;
  link.removeAttribute('target');
  link.removeAttribute('rel');
});

function beep(frequency = 420, duration = 0.035, volume = 0.025) {
  if (!soundOn) return;
  audioContext ??= new AudioContext();
  const oscillator = audioContext.createOscillator();
  const gain = audioContext.createGain();
  oscillator.type = 'square';
  oscillator.frequency.value = frequency;
  gain.gain.setValueAtTime(volume, audioContext.currentTime);
  gain.gain.exponentialRampToValueAtTime(0.001, audioContext.currentTime + duration);
  oscillator.connect(gain).connect(audioContext.destination);
  oscillator.start();
  oscillator.stop(audioContext.currentTime + duration);
}

function activateTab(name, updateHash = true) {
  tabs.forEach((tab) => {
    const active = tab.dataset.tab === name;
    tab.classList.toggle('active', active);
    tab.setAttribute('aria-selected', active);
  });
  panels.forEach((panel) => {
    const active = panel.id === `tab-${name}`;
    panel.classList.toggle('active', active);
    panel.hidden = !active;
  });
  command.textContent = `access --${name}`;
  beep(180, .06, .035);
  if (updateHash) history.pushState({ tab: name }, '', `#${name}`);
}

tabs.forEach((tab) => tab.addEventListener('click', () => activateTab(tab.dataset.tab)));
document.querySelectorAll('a').forEach((link) => link.addEventListener('click', () => beep(620, .025)));
window.addEventListener('popstate', () => activateTab(location.hash.slice(1) || 'overview', false));

const overview = document.querySelector('#tab-overview');
if (overview) {
  overview.querySelector('.panel-heading > div')?.insertAdjacentHTML('afterbegin', '<img class="home-logo" src="https://cdn.jsdelivr.net/gh/davidsmod/the-broken-wiki@refs/heads/main/assets/images/0073_Boob_(my_friend_named_this).png" alt="The Broken Script logo" width="96" height="96">');
  overview.insertAdjacentHTML('beforeend', `<div class="home-metrics"><article><b>161</b><span>LOCAL ARTICLES</span><small>OFFICIAL WIKI MIRROR</small></article><article><b>1,771</b><span>ARCHIVED ASSETS</span><small>IMAGE / AUDIO / VIDEO</small></article><article><b>06</b><span>MAIN SECTIONS</span><small>LORE TO COMMUNITY</small></article></div><div class="home-directory"><div><span class="overline">DIRECTORY // QUICK ACCESS</span><h2>ARCHIVE ROUTES</h2></div><a href="wiki-pages/index.html">SEARCH ALL ENTRIES <b>→</b></a><a href="#entities" data-tab-jump="entities">ENTITY INDEX <b>→</b></a><a href="#content" data-tab-jump="content">MOD CONTENT <b>→</b></a><a href="#technical" data-tab-jump="technical">TECHNICAL FILES <b>→</b></a></div>`);
  overview.querySelectorAll('[data-tab-jump]').forEach((link) => link.addEventListener('click', (event) => { event.preventDefault(); activateTab(link.dataset.tabJump); }));
}

const initialTab = location.hash.slice(1);
activateTab(tabs.some((tab) => tab.dataset.tab === initialTab) ? initialTab : 'overview', false);

setInterval(() => {
  clock.textContent = new Date().toLocaleTimeString('fr-FR', { hour12: false });
}, 1000);

soundButton.addEventListener('click', async () => {
  soundOn = !soundOn;
  if (soundOn) {
    audioContext ??= new AudioContext();
    await audioContext.resume();
    archiveAudio.play().catch(() => {});
    beep(520, .08, .04);
  } else {
    archiveAudio.pause();
  }
  soundButton.textContent = `SOUND: ${soundOn ? 'ON' : 'OFF'}`;
  soundButton.setAttribute('aria-pressed', soundOn);
});
