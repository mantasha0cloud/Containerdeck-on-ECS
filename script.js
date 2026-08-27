function updateClock() {
  const now = new Date();
  document.getElementById('clock').textContent = now.toLocaleTimeString();
}

document.getElementById('deployTime').textContent = new Date().toLocaleString();

setInterval(updateClock, 1000);
updateClock();
