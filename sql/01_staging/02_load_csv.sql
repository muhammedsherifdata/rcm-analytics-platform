/* 02_load_csv.sql
   Loads the raw CSVs as-is into stg.* (no cleaning, no rejection).
   Edit @path to the folder holding the CSVs (readable by the SQL Server service account). */
USE RCM;
GO
DECLARE @path NVARCHAR(260) = N'C:\RCM_Data\raw\';
DECLARE @t NVARCHAR(50), @sql NVARCHAR(MAX);
DECLARE c CURSOR FOR SELECT v FROM (VALUES ('payers'),('providers'),('patients'),('claims'),('remittances'),('denials')) x(v);
OPEN c; FETCH NEXT FROM c INTO @t;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'TRUNCATE TABLE stg.' + @t + N';
    BULK INSERT stg.' + @t + N' FROM ''' + @path + @t + N'.csv''
    WITH (FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'',
          CODEPAGE = ''65001'', KEEPNULLS, TABLOCK);';
    EXEC sp_executesql @sql;
    FETCH NEXT FROM c INTO @t;
END
CLOSE c; DEALLOCATE c;
GO

/* Load-level control: rows loaded vs rows in the CSV */
SELECT t.tbl, t.loaded, t.expected,
       CASE WHEN t.loaded = t.expected THEN 'OK' ELSE 'MISMATCH' END AS status
FROM (
    SELECT 'payers' tbl, COUNT(*) loaded, 16 expected FROM stg.payers UNION ALL
    SELECT 'providers', COUNT(*), 12 FROM stg.providers UNION ALL
    SELECT 'patients', COUNT(*), 20000 FROM stg.patients UNION ALL
    SELECT 'claims', COUNT(*), 60720 FROM stg.claims UNION ALL
    SELECT 'remittances', COUNT(*), 49569 FROM stg.remittances UNION ALL
    SELECT 'denials', COUNT(*), 7424 FROM stg.denials) t;
