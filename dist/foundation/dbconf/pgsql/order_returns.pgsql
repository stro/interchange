Database  order_returns  order_returns.txt __SQLDSN__
ifdef SQLUSER
Database  order_returns  USER         __SQLUSER__
endif
ifdef SQLPASS
Database  order_returns  PASS         __SQLPASS__
endif
Database  order_returns  COLUMN_DEF   "code=varchar(14) NOT NULL PRIMARY KEY"
Database  order_returns  COLUMN_DEF   "order_number=VARCHAR(14) NOT NULL"
Database  order_returns  COLUMN_DEF   "session=VARCHAR(32) NOT NULL"
Database  order_returns  COLUMN_DEF   "username=VARCHAR(20) default '' NOT NULL"
Database  order_returns  COLUMN_DEF   "rma_number=VARCHAR(32) NOT NULL"
Database  order_returns  COLUMN_DEF   "nitems=VARCHAR(9) NOT NULL"
Database  order_returns  COLUMN_DEF   "total=VARCHAR(12) NOT NULL"
Database  order_returns  COLUMN_DEF   "return_date=varchar(32) NOT NULL"
Database  order_returns  COLUMN_DEF   "update_date=timestamp"
Database  order_returns  POSTCREATE   "create index order_returns_order_number on order_returns (order_number)"
