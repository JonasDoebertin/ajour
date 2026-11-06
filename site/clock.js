const weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

const twoDigits = (number) => String(number).padStart(2, "0");

export function formatMenuBarClock(date) {
  const day = `${weekdays[date.getDay()]} ${date.getDate()} ${months[date.getMonth()]}`;
  const time = `${twoDigits(date.getHours())}:${twoDigits(date.getMinutes())}`;
  return `${day}  ${time}`;
}

function keepShowingTheTime(element) {
  const now = new Date();
  element.textContent = formatMenuBarClock(now);
  const untilNextMinute = 60_000 - now.getSeconds() * 1_000 - now.getMilliseconds();
  setTimeout(() => keepShowingTheTime(element), untilNextMinute);
}

const clock = globalThis.document?.querySelector(".clock");
if (clock) {
  keepShowingTheTime(clock);
}
