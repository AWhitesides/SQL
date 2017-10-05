-- list MSSQL Server Verson
SELECT @@VERSION ;

-- LIST ARCSDE VERSION
SELECT * FROM SDE_VERSION ;

-- LIST SERVER_CONFIG 
SELECT PROP_NAME, NUM_PROP_VALUE FROM SDE_SERVER_CONFIG ;
--SELECT CONFIG_STRING FROM SDE_DBTUNE WHERE PARAMETER_NAME = 'SESSION_TEMP_TABLE' ;

-- Current connections:
select DB_NAME(dbid) as DBName ,
Count(dbid)/4 as 'tot conn'
from master.dbo.sysprocesses 
where program_name like '%sde:%'
and dbid > 0
group by dbid

select 
 (select COUNT(*) from SDE_process_information) as [Current Connections]
 , num_prop_value as [max connections] 
from SDE_server_config where prop_name = 'Connections' 

-- How many connections frow what sources
select nodename,
Count(nodename) as 'tot conn'
from SDE_process_information
group by nodename

-- oldest connection(s) 
select 
	 [owner]
	, start_time
	, datediff(hh,start_time,getdate()) as HoursActive
	, nodename
 from SDE_process_information
 order by start_time asc

---------------------------------------------------------------------- 

--  number of current Versions
	select count(*) from sde.dbo.SDE_versions
-- number of States
	select count(*) from sde.dbo.SDE_states
-- number of State_Lineages
	select count(*) from sde.dbo.SDE_State_Lineages
-- Lineage_Depth_Default
	select count(*) as depth 
	from sde.dbo.SDE_state_lineages 
	where lineage_name in 
		(select lineage_name 
		 from sde.dbo.SDE_states 
		 where state_id in 
		 (select state_id 
		  from sde.dbo.SDE_versions 
		  where name = 'DEFAULT')
		);

-- Last Compression
	select top(1) * from dbo.sde_compress_log order by compress_end desc

-- frequecncy run (time between counts)
	select  c.compress_id
			, datediff(MINUTE,c.compress_start,c.compress_end) as Runtime
			, c.start_state_count, c.end_state_count
			, ((c.start_state_count - c.end_state_count)/((c.start_state_count + c.end_state_count)/2) *100) as PercentageChange
			, c.compress_status
			, datediff(DAY,(select compress_start from dbo.sde_compress_log where compress_id = (c.compress_id-1)),c.compress_start) DaysBetweenCompresses
			, c.compress_start
			, c.compress_end
			 from dbo.sde_compress_log c
			 order by c.compress_end desc
			 

-- Last Time to state 0
	select  max(compress_end) 
	from dbo.sde_compress_log 
	where end_state_count = 1

-- Somehting to tell the last reconcile for each version

-- ------------------------------------------------------------------------
-- which replica is assocaited with each replica.

-- LIST GDB OBJECT COUNTS
SELECT GDB_ITEMTYPES.OBJECTID,
  GDB_ITEMTYPES.NAME AS OJBECT_TYPE,
  COUNT(0)               AS COUNT
FROM GDB_ITEMTYPES
INNER JOIN GDB_ITEMS
ON GDB_ITEMS.TYPE = GDB_ITEMTYPES.UUID
GROUP BY GDB_ITEMTYPES.OBJECTID,
  GDB_ITEMTYPES.NAME
ORDER BY GDB_ITEMTYPES.OBJECTID ASC


--------------------------------------------------------------------------------
/* Find all versioned feature classes in 10.x database
from help: http://help.arcgis.com/en/arcgisdesktop/10.0/help/index.html#/Determining_which_data_is_versioned/006z000000v1000000/
*/

SELECT NAME AS "Versioned feature class" 
FROM dbo.GDB_ITEMS
WHERE Definition.exist('(/*/Versioned)[1]') = 1
AND Definition.value('(/*/Versioned)[1]', 'nvarchar(4)') = 'true'

select 
	i.Name
	,it.name as ItemType
./	,PhysicalName
	,[Path]
	,Url
	,Properties
	,[Definition] 
	,[Definition].value('Versioned[1]','varchar(10)') as Versioned
 from dbo.GDB_ITEMS i inner join dbo.GDB_ITEMTYPES it on i.Type = it.UUID

------------dBinfo-------------------------------------------------------------------
SELECT Name [Database]
		,Physical_Name [Physical file Location]
		,size*8/1024 [Size_MB]
		,Database_id 
		,Type_desc
FROM sys.master_files 
----------------------------------------
 qw\
 _users_login 'report'

 -- add size of base table to this 
 --------------  look for big a tables --------------------------------------------
SELECT s.[Name]    AS [Schema] 
       ,t.[name]    AS [Table]
	   , r.table_name AS BaseTable
       ,SUM(p.ROWS) AS [RowCount] 
FROM   sys.schemas s 
       LEFT JOIN sys.tables t 
         ON s.schema_id = t.schema_id 
       LEFT JOIN sys.partitions p 
         ON t.object_id = p.object_id 
       LEFT JOIN sys.allocation_units a 
         ON p.partition_id = a.container_id
	   LEFT JOIN SDE_table_registry r
	     ON SUBSTRING (t.[name] , 2, 8000) = r.registration_id 
WHERE  p.index_id IN( 0, 1 ) -- 0 heap table , 1 table with clustered index 
       AND p.ROWS IS NOT NULL 
       AND a.TYPE = 1 -- row-data only , not LOB 
       AND t.name IN (SELECT 'A' + CONVERT(VARCHAR, registration_id) 
                      FROM   sde_table_registry) 
GROUP  BY s.[Name] 
         ,t.[name] 
		 ,r.table_name
Having sum(p.rows) > 0
ORDER  BY 4 desc


--------- all tables crated past a certian date
Declare @SearchDate datetime 
set @SearchDate = '09-15-2010 00:00:00' -- Put your search date here

select
	tr.table_name
	,DATEADD(ss, tr.registration_date, '01-01-1970 00:00:00') as DateAdded
from dbo.SDE_table_registry tr
 where tr.registration_date > DATEDIFF(ss, '01-01-1970 00:00:00', @SearchDate)
-------------------------------------------------------------------------------------------

-------------------------------------------------------------------------------------------
--Table Fragmentation
SELECT 
	dbschemas.[name] as 'Schema' 
	,dbtables.[name] as 'Table' 
	,dbindexes.[name] as 'Index'
	,indexstats.avg_fragmentation_in_percent as '% Avg Frag'
	,indexstats.page_count as 'Page Cnt'
	,indexstats.fragment_count
FROM sys.dm_db_index_physical_stats (DB_ID(), NULL, NULL, NULL, NULL) AS indexstats
	INNER JOIN sys.tables dbtables on dbtables.[object_id] = indexstats.[object_id]
	INNER JOIN sys.schemas dbschemas on dbtables.[schema_id] = dbschemas.[schema_id]
	INNER JOIN sys.indexes AS dbindexes ON dbindexes.[object_id] = indexstats.[object_id]
		AND indexstats.index_id = dbindexes.index_id
WHERE indexstats.database_id = DB_ID()
	and indexstats.avg_fragmentation_in_percent > 30
	and indexstats.page_count > 100
ORDER BY indexstats.avg_fragmentation_in_percent DESC

-------------------------------------------------------------------------------------------
DBCC LOGINFO
--DBCC SHRINKFILE(transactionloglogicalfilename, TRUNCATEONLY)


DECLARE @path NVARCHAR(255) = N'\\backup_share\log\yourdb_' 
  + CONVERT(CHAR(8), GETDATE(), 112) + '_'
  + REPLACE(CONVERT(CHAR(8), GETDATE(), 108),':','')
  + '.trn';

BACKUP LOG foo TO DISK = @path WITH INIT, COMPRESSION;
-------------------------------------------------------------------------------------------

sp_configure 'show advanced options', 1;
GO
RECONFIGURE;
GO
sp_configure 'clr enabled', 1;
GO
RECONFIGURE;
GO

-------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------
