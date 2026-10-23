const tabs = [...document.querySelectorAll('.tab')];
const panels = [...document.querySelectorAll('.tab-panel')];
const command = document.querySelector('#typed-command');
const clock = document.querySelector('#clock');
const soundButton = document.querySelector('#sound-toggle');
let audioContext;
let soundOn = false;

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
  if (updateHash) history.replaceState(null, '', `#${name}`);
}

tabs.forEach((tab) => tab.addEventListener('click', () => activateTab(tab.dataset.tab)));
document.querySelectorAll('a').forEach((link) => link.addEventListener('click', () => beep(620, .025)));

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
    beep(520, .08, .04);
  }
  soundButton.textContent = `SOUND: ${soundOn ? 'ON' : 'OFF'}`;
  soundButton.setAttribute('aria-pressed', soundOn);
});
