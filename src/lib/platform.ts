export function isMacDesktop(): boolean {
  if (typeof navigator === "undefined") return true;
  const ua = navigator.userAgent;
  const platform = navigator.platform || "";
  const mac = /Mac/i.test(platform) || /Macintosh/i.test(ua);
  return mac && !/iPhone|iPad|iPod|Android/i.test(ua);
}
