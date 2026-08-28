# BSC HR Stock — stock.bharatsteels.in

Static dashboard + daily WhatsApp stock report for Bharat Steel (Chennai).
Same model as the weighbridge dashboard: PowerShell pushes CSVs from SAP, GitHub Pages serves the app. No login.

## Files
| File | Purpose |
|---|---|
| `index.html` | Interactive dashboard (Coils / Plates tabs, filters, chart) |
| `report.html` | Print-styled report that mirrors the Excel pivot — screenshotted to PNG for WhatsApp |
| `refresh_stock.ps1` | Runs both SAP queries → writes `coils.csv` / `plates.csv` → git push |
| `coils.csv` / `plates.csv` | Data (sample committed; first real refresh overwrites) |

## Deploy (one time)
1. Create GitHub repo **BSC23609/bsc-stock-data**, push these files.
2. Repo → Settings → Pages → deploy from `main` / root.
3. Add custom domain `stock.bharatsteels.in` (CNAME file already here); point the DNS CNAME at `bsc23609.github.io`.

## Data pipeline (on the SAP box)
1. Clone once: `git clone https://github.com/BSC23609/bsc-stock-data C:\github\bsc-stock-data`
2. Put DB creds in `C:\scripts\config.ini` (see header of `refresh_stock.ps1`).
3. Schedule `refresh_stock.ps1` the same way as the weighbridge refresh.
   Run manually to test: `powershell -ExecutionPolicy Bypass -File C:\scripts\refresh_stock.ps1`

## Daily WhatsApp  (next step — separate Render service)
report.html → headless screenshot → PNG → WATI image-header template → the two numbers, 9:00 AM Mon–Sat via cron-job.org.
