# BSC Stock · Sales · Purchase MIS — stock.bharatsteels.in

Static dashboards + daily WhatsApp MIS report for Bharat Steel (Chennai).
Same model as the weighbridge dashboard: PowerShell pushes CSVs from SAP, GitHub Pages serves the app. No login.

## Files
| File | Purpose |
|---|---|
| `index.html` | HR stock detail (Coils / Plates tabs, batch drill-down, filters, chart) |
| `stock-master.html` | **Stock Master** — live SAP stock by location (Chennai 11/38, Salem 22/07, transit), brand→grade tree, thickness×width pivot with cell drill-down, full item list with CSV export, and WH-38 coil batch/bin/age detail. Reads `mis_stock.csv` + `coils.csv`. |
| `mis.html` | **MIS dashboard** — Overview (the 4 Excel pivots), Sales, Purchase, Stock tabs with FY / month selector, category → group → item drill-down, top customers / vendors, warehouse × category drill-down |
| `report.html` | Print-styled page mirroring the whole Excel MIS sheet — screenshotted to PNG for WhatsApp |
| `refresh_stock.ps1` | Runs all 5 SAP queries → writes the CSVs below + `mis_meta.json` → single git push (lock-protected) |
| `setup_task.ps1` | One-shot: registers the 15-min Task Scheduler job |
| `coils.csv` / `plates.csv` | HR stock detail data |
| `mis_stock.csv` | Every item × warehouse with OnHand > 0, with the pivot category (mirrors SAP query "Warehouse Stock Report") |
| `mis_sales.csv` | A/R invoice lines from start of previous FY, grouped category × group × item × customer × month (mirrors "Sales Report") |
| `mis_purchase.csv` | A/P invoice lines, same shape, categorised by line `U_MOU` (mirrors "Purchase") |
| `mis_jobwork_flow.csv` | Warehouse 45 movements by month / type / party (received, processed, dispatched) |
| `mis_jobwork_docs.csv` | Deliveries and invoices tagged *Job Work* by the VSP add-on, with delivered-not-invoiced qty |
| `mis_jobwork_balance.csv` | Batches lying in warehouse 45 with owner and age |
| `mis_meta.json` | Refresh timestamp + row counts; the pages show "STALE" if it is > 3 h old |

Sample MIS CSVs are committed from the discovery run (group-level only); the first scheduled refresh replaces them with live item-level data.

## Deploy (one time)
1. Create GitHub repo **BSC23609/bsc-stock-data**, push these files.
2. Repo → Settings → Pages → deploy from `main` / root.
3. Add custom domain `stock.bharatsteels.in` (CNAME file already here); point the DNS CNAME at `bsc23609.github.io`.

## Data pipeline (on the SAP box)
1. Clone once: `git clone https://github.com/BSC23609/bsc-stock-data C:\github\bsc-stock-data`
2. Put DB creds in `C:\scripts\config.ini` (see header of `refresh_stock.ps1`).
3. Test once by hand: `powershell -ExecutionPolicy Bypass -File C:\scripts\refresh_stock.ps1`
4. Schedule it: `powershell -ExecutionPolicy Bypass -File C:\scripts\setup_task.ps1` (elevated; runs every 15 min)

## Reconciliation notes
- Stock categories, warehouse exclusions (45 job-work, 46 consumables) and the sales / purchase filters
  (`Canceled='N'`, `GSTTranTyp<>'GD'`, `Quantity>0`, `BaseType<>13/18`) are copied from the SAP saved queries that feed the Excel pivot.
- Sales category comes from the item group; purchase category comes from the line-level `U_MOU` UDF (so NMDC / TMT-EQR show as their own rows, as in Excel).
- Job work (customer-owned coils, e.g. Wheels India): items `JW…` in group "HR Coil", warehouse 45, documents tagged `U_VSPJWTX='Job Work'`.
  `mis_sales.csv` carries a `JW` flag; the pages show own-material sales in the category rows and job-work conversion tonnage as a separate line.
- Stock Master shows warehouses 11, 38, 22, 07, 39, 50, 51, 52 (excludes job-work 45 and consumables 46). Salem = WH 22 + 07; it reconciles to the old Salem sheet (989.8 t WH22 ≈ 977 t sheet). Stale open-PO quantities on some structurals are clamped out of the Incoming column and flagged in the footer count.
- Financial year = 1 April; data is pulled from the start of the previous FY so the FY selector can compare years.

## Daily WhatsApp  (next step — separate Render service)
report.html → headless screenshot → PNG → WATI image-header template → the two numbers, 9:00 AM Mon–Sat via cron-job.org.
