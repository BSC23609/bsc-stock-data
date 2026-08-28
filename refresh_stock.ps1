<#
  refresh_stock.ps1 — HR stock pipeline for stock.bharatsteels.in
  Queries SAP MSSQL, writes coils.csv + plates.csv into the repo, pushes to GitHub.
  Run from PowerShell (NOT cmd — a .ps1 opens in Notepad from cmd):
      powershell -ExecutionPolicy Bypass -File C:\scripts\refresh_stock.ps1
  Schedule it the same way as the weighbridge refresh.

  Config: reuse C:\scripts\config.ini  (gitignored) with:
      [db]
      server=10.10.250.11
      database=BSC_FINAL_2707
      user=sa
      password=YOURPASS
#>

$ErrorActionPreference = "Stop"
$RepoDir  = "C:\github\bsc-stock-data"
$Cfg      = "C:\scripts\config.ini"
$LogFile  = "C:\scripts\refresh_stock.log"

function Log($m){ "$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))  $m" | Tee-Object -FilePath $LogFile -Append }

# ---- read config.ini ----
$ini=@{}; Get-Content $Cfg | ForEach-Object {
  if($_ -match '^\s*([^=;#\[]+)=(.*)$'){ $ini[$matches[1].Trim()]=$matches[2].Trim() }
}
$connStr="Server=$($ini.server);Database=$($ini.database);User Id=$($ini.user);Password=$($ini.password);TrustServerCertificate=True;Connect Timeout=30"

function Invoke-Sql($sql){
  $conn=New-Object System.Data.SqlClient.SqlConnection $connStr
  $conn.Open()
  $cmd=$conn.CreateCommand(); $cmd.CommandText=$sql; $cmd.CommandTimeout=120
  $da=New-Object System.Data.SqlClient.SqlDataAdapter $cmd
  $dt=New-Object System.Data.DataTable; [void]$da.Fill($dt)
  $conn.Close(); return $dt
}

# ---- brand parsed from item name (mill), not the steel grade UDF ----
function Get-Brand($name){
  $n=($name -replace 'H\.R','HR').ToUpper().Trim()
  foreach($b in @('NMDC','SAIL','JSW','AMNS','RINL','JINDAL','TATA','POSCO')){
    if($n.StartsWith($b)){ return $b }
  }
  return 'OTHER'
}

# ======================= QUERIES =======================
$coilSql = @"
SELECT
    T0.ItemCode, I.ItemName, I.U_Grade AS [Grade],
    CAST(I.U_Thick AS DECIMAL(18,2)) AS [Thickness],
    CAST(I.U_Width AS INT) AS [Width],
    CAST(I.U_Length1 AS INT) AS [Length],
    T0.BatchNum, T0.U_CoilNo,
    T0.Quantity, T0.WhsCode,
    B.BinCode AS [Bin],
    T0.BaseNum AS [GRPONo],
    (SELECT MAX(A.DocDate) FROM OPDN A WHERE A.DocNum = T0.BaseNum) AS [GRPODate]
FROM OIBT T0
INNER JOIN OITM I ON T0.ItemCode = I.ItemCode
LEFT JOIN OBTN BT ON BT.ItemCode = T0.ItemCode AND BT.DistNumber = T0.BatchNum
LEFT JOIN OBBQ Q  ON Q.ItemCode = BT.ItemCode AND Q.SnBMDAbs = BT.AbsEntry AND Q.WhsCode = T0.WhsCode
LEFT JOIN OBIN B  ON B.AbsEntry = Q.BinAbs
WHERE T0.Quantity > 0 AND T0.WhsCode = '38'
ORDER BY T0.ItemCode, T0.BatchNum, B.BinCode
"@

$plateSql = @"
WITH InventoryData AS (
    SELECT T.ItemCode, I.ItemName, I.U_Grade, I.U_Thick, I.U_Width, I.U_Length1,
        (T.InQty - T.OutQty) AS NetQty,
        CASE
            WHEN T.TransType = 59 THEN ISNULL(GR.U_OutPcs, ISNULL(IGN1.U_Nos, 0))
            WHEN T.TransType = 60 THEN -1 * ISNULL(GI.U_OutPcs, ISNULL(IGE1.U_Nos, 0))
            WHEN T.TransType = 14 THEN -1 * ISNULL(RIN1.U_Nos, 0)
            WHEN T.OutQty > 0 THEN -1 * ISNULL(COALESCE(INV1.U_Nos, PCH1.U_Nos, DLN1.U_Nos, RDN1.U_Nos, RIN1.U_Nos, RPC1.U_Nos, WTR1.U_Nos), 0)
            ELSE ISNULL(COALESCE(INV1.U_Nos, PCH1.U_Nos, DLN1.U_Nos, RDN1.U_Nos, RIN1.U_Nos, RPC1.U_Nos, WTR1.U_Nos), 0)
        END AS RowNos
    FROM OINM T
    INNER JOIN OITM I ON I.ItemCode = T.ItemCode
    LEFT JOIN (SELECT U_GRDocEty, U_OPItem, U_GRLineNo, SUM(CAST(U_ActRcpt AS DECIMAL(19,6))) AS U_OutPcs FROM [@SMS_SHE1] GROUP BY U_GRDocEty, U_OPItem, U_GRLineNo) GR
        ON T.TransType = 59 AND GR.U_GRDocEty = T.CreatedBy AND GR.U_OPItem = T.ItemCode AND GR.U_GRLineNo = T.DocLineNum
    LEFT JOIN (SELECT U_GIDocEty, U_OPItem, U_GILineNo, SUM(CAST(U_InputPcs AS DECIMAL(19,6))) AS U_OutPcs FROM [@SMS_SHE1] GROUP BY U_GIDocEty, U_OPItem, U_GILineNo) GI
        ON T.TransType = 60 AND GI.U_GIDocEty = T.CreatedBy AND GI.U_OPItem = T.ItemCode AND GI.U_GILineNo = T.DocLineNum
    LEFT JOIN INV1 ON T.TransType = 13 AND INV1.DocEntry = T.CreatedBy AND INV1.LineNum = T.DocLineNum
    LEFT JOIN PCH1 ON T.TransType = 18 AND PCH1.DocEntry = T.CreatedBy AND PCH1.LineNum = T.DocLineNum
    LEFT JOIN DLN1 ON T.TransType = 15 AND DLN1.DocEntry = T.CreatedBy AND DLN1.LineNum = T.DocLineNum
    LEFT JOIN RDN1 ON T.TransType = 16 AND RDN1.DocEntry = T.CreatedBy AND RDN1.LineNum = T.DocLineNum
    LEFT JOIN RIN1 ON T.TransType = 14 AND RIN1.DocEntry = T.CreatedBy AND RIN1.LineNum = T.DocLineNum
    LEFT JOIN RPC1 ON T.TransType = 19 AND RPC1.DocEntry = T.CreatedBy AND RPC1.LineNum = T.DocLineNum
    LEFT JOIN WTR1 ON T.TransType = 67 AND WTR1.DocEntry = T.CreatedBy AND WTR1.LineNum = T.DocLineNum
    LEFT JOIN IGN1 ON T.TransType = 59 AND IGN1.DocEntry = T.CreatedBy AND IGN1.LineNum = T.DocLineNum
    LEFT JOIN IGE1 ON T.TransType = 60 AND IGE1.DocEntry = T.CreatedBy AND IGE1.LineNum = T.DocLineNum
)
SELECT ItemCode, MAX(ItemName) AS ItemName, MAX(U_Grade) AS Grade,
    MAX(U_Thick) AS Thickness, MAX(U_Width) AS Width, MAX(U_Length1) AS Length,
    SUM(NetQty) AS TotalQty, SUM(RowNos) AS TotalNos
FROM InventoryData
WHERE ItemCode LIKE 'HRC%'
GROUP BY ItemCode
HAVING SUM(NetQty) <> 0 OR SUM(RowNos) <> 0
ORDER BY ItemCode
"@

# ======================= RUN =======================
try{
  Log "Querying coils…"
  $coils = Invoke-Sql $coilSql
  Log "  $($coils.Rows.Count) coil rows"

  Log "Querying plates…"
  $plates = Invoke-Sql $plateSql
  Log "  $($plates.Rows.Count) plate rows"

  # ---- build coils.csv (add Brand, tidy GRPODate) ----
  $coilOut = foreach($r in $coils.Rows){
    [PSCustomObject]@{
      ItemCode=$r.ItemCode; ItemName=$r.ItemName; Brand=(Get-Brand $r.ItemName)
      Grade=$r.Grade; Thickness=$r.Thickness; Width=$r.Width; Length=$r.Length
      BatchNum=$r.BatchNum; CoilNo=$r.U_CoilNo; Quantity=$r.Quantity
      WhsCode=$r.WhsCode; Bin=$r.Bin; GRPONo=$r.GRPONo
      GRPODate=if($r.GRPODate -is [DateTime]){ $r.GRPODate.ToString('yyyy-MM-dd') } else { '' }
    }
  }
  # ---- build plates.csv ----
  $plateOut = foreach($r in $plates.Rows){
    [PSCustomObject]@{
      ItemCode=$r.ItemCode; ItemName=$r.ItemName; Brand=(Get-Brand $r.ItemName)
      Grade=$r.Grade; Thickness=$r.Thickness; Width=$r.Width; Length=$r.Length
      TotalQty=$r.TotalQty; TotalNos=$r.TotalNos
    }
  }

  # write WITHOUT BOM (dashboard strips BOM anyway, but keep it clean)
  $enc=New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText("$RepoDir\coils.csv",  ($coilOut  | ConvertTo-Csv -NoTypeInformation) -join "`r`n", $enc)
  [IO.File]::WriteAllText("$RepoDir\plates.csv", ($plateOut | ConvertTo-Csv -NoTypeInformation) -join "`r`n", $enc)
  Log "CSVs written."

  # ---- push (pull-first to avoid the race we hit on weighbridge) ----
  Push-Location $RepoDir
  git pull --quiet 2>&1 | Out-Null
  git add coils.csv plates.csv
  $stamp=[DateTime]::Now.ToString('yyyy-MM-dd HH:mm')
  git commit -m "stock refresh $stamp" 2>&1 | Out-Null
  git push --quiet 2>&1 | Out-Null
  Pop-Location
  Log "Pushed. Done."
}
catch{
  Log "ERROR: $($_.Exception.Message)"
  exit 1
}
