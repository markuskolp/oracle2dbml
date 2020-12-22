/**********************************************************************************
Oracle to DBML script (for 1 schema)

see: https://www.dbml.org/docs
                  
1. Check that you have the rights to query the Oracle metadata tables 
2. Run the script (you are asked to enter a Schema Name) and export the result to a new text file with ending '*.dbml'. You can run the script manually, use SQLplus or another tool of your choice. 
   (you can easily adjust the script, if you want to see more than just 1 Schema)
3. Then just use the resulting DBML file :-) (e.g. test it on https://dbdiagram.io/ or generate a documentation website with https://dbdocs.io/)

A few lines are still marked with `to be done`. So feel free to give feedback or wait for further updates.
                  
**********************************************************************************/

------------------------------------------
-- a few prepared statements
------------------------------------------
with 
-- database metadata
dv as (select banner from v$version where banner like 'Oracle%')
, dh as (select sys_context ( 'USERENV', 'DB_NAME' ) db_name, sys_context ( 'USERENV', 'SESSION_USER' ) user_name, sys_context ( 'USERENV', 'SERVER_HOST' ) db_host, sys_context ( 'USERENV', 'HOST' ) user_host from dual)
-- table metadata
, t as (
    select 
        a.owner as schema, a.table_name
        , decode(a.partitioned, 'YES', 'Y', 'N') as has_partitioning
        , decode(a.logging, 'YES', 'Y', 'N') as has_logging
        , comments as table_comment
    from sys.all_tables a, sys.all_tab_comments ac
    where 1=1
    and a.owner = :schema and a.owner = ac.owner(+) and a.table_name = ac.table_name(+)
)
-- columns metadata
, c as (
   select 
    a.owner as schema, a.table_name, a.column_name, a.column_id as column_sort
    , decode(a.data_type, 'LONG RAW', 'LONG', a.data_type) || case when a.data_type like 'TIMESTAMP%' or a.data_length is null or a.data_length = 0 then '' else '('||a.data_length|| case when a.character_set_name is null then '' else ' ' || decode(a.character_set_name, 'CHAR_CS', 'CHAR', a.character_set_name) end || ')' end as data_type
    , replace(ac.comments, '''', '\''') as column_comment
    , a.nullable as is_nullable
    , null as default_value -- to be done: a.data_default is a LONG datatype and has to be converted to VARCHAR2 - probably a function is necesarry for that
   from sys.all_tab_columns a,sys.all_col_comments ac
   where 1=1
   and a.owner = :schema and a.owner = ac.owner(+) and a.table_name = ac.table_name(+) and a.column_name = ac.column_name(+)
)
-- constraints metadata
, cct as (
    select
       decode(a.constraint_type, 'P', 'PK', 'R', 'FK', 'U', 'UK', 'C', 'CHECK', '?') as type
       , acc.owner as schema
       , acc.table_name 
       , a.constraint_name
       , acc.column_name
       , acc.position as column_order
       , a.status -- enabled or disabled
       , a.r_constraint_name as ref_constraint_name
    from sys.all_constraints a, sys.all_cons_columns acc
    where 1=1 
       and a.constraint_name = acc.constraint_name
       and a.owner = acc.owner
       and a.owner = 'COGNOS_CONTENTSTORE'
    order by 
       acc.owner,
       acc.table_name, 
       acc.position
)
, pk as ( select * from cct where type = 'PK') -- primary keys
, uk as ( select * from cct where type = 'UK') -- unique columns
, fk as (select cct.* , fk.schema as fk_schema, fk.table_name as fk_table_name, fk.column_name as fk_column_name from cct, cct fk where cct.type = 'FK' and cct.ref_constraint_name = fk.constraint_name and cct.schema = :schema and fk.schema = :schema) -- foreign keys

------------------------------------------
-- define project (here it's just the schema of the database)
------------------------------------------

select 
'Project ' || :schema || ' { 
  database_type: ''Oracle''
  Note: ''jdbc:oracle:thin:@'||dh.db_host||':1521:'||dh.db_name||' / Database version: ' || dv.banner || ''' 
}' as dbml    -- define a note as you want. here for example we generate the JDBC URL and also document the database version
, '001' as sort
from 
    dual
    , dv
    , dh

union all

------------------------------------------
-- all tables 
------------------------------------------

-- table header
select 'Table ' || lower(t.table_name) || ' {' as dbml, '002_table_' || t.table_name || '_001_header' as sort from t

union all

-- table footer
select '  Note: ''' || t.table_comment || ''' 
}' as dbml, '002_table_' || t.table_name || '_020_footer' as sort from t


union all

------------------------------------------
-- columns
------------------------------------------
    -- to be done: make Oracle data type generic
    -- to be done: default_value (cast long to varchar2)
select 
'  ' || lower(c.column_name)|| ' ' || lower(c.data_type) || ' [' 
    || case when pk.constraint_name is not null then 'pk, ' else '' end 
    || case when uk.constraint_name is not null then 'unique, ' else '' end 
    || case when c.default_value is not null then 'default: '||c.default_value||', ' else '' end 
    || case when c.is_nullable = 'N' then 'not null, ' else '' end 
    || 'note: '''||c.column_comment||''']' as dbml
, '002_table_' || t.table_name || '_010_column_' || substr('00'||c.column_sort,-3) || '_' || c.column_name as sort

from 
    t
    , c
    , pk
    , uk
where 1=1
and t.schema = c.schema and t.table_name = c.table_name
and c.schema = pk.schema(+) and c.table_name = pk.table_name(+) and c.column_name = pk.column_name(+)
and c.schema = uk.schema(+) and c.table_name = uk.table_name(+) and c.column_name = uk.column_name(+)

union all

------------------------------------------
-- relationships
------------------------------------------

-- Ref name_optional: table1.column1 < table2.column2
-- <: one-to-many. E.g: users.id < posts.user_id
-- >: many-to-one. E.g: posts.user_id > users.id
-- -: one-to-one. E.g: users.id - user_infos.user_id

select 
    'Ref: ' || lower(fk.table_name) || '.' || lower(fk.column_name) || ' > ' || lower(fk.fk_table_name) || '.' || lower(fk.fk_column_name)
    , '002_table_' || fk.table_name || '_030_ref_' || fk.column_order || '_' || fk.constraint_name as sort
from fk

------------------------------------------

order by sort

;



