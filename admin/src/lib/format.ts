const inr = new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 2 });
const ist = new Intl.DateTimeFormat("en-IN", {
  timeZone: "Asia/Kolkata", day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit",
});

export const rupees = (paise: number | null | undefined) => inr.format((paise ?? 0) / 100);
export const rupeesWhole = (r: number) => inr.format(r);
export const istDate = (iso: string | null | undefined) => (iso ? `${ist.format(new Date(iso))} IST` : "—");
export const bytes = (n: number) => {
  const u = ["B", "KB", "MB", "GB", "TB"];
  let i = 0;
  let v = n;
  while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
  return `${v.toFixed(i === 0 ? 0 : 1)} ${u[i]}`;
};
