LOAD DATA LOCAL INFILE '/Users/bouzer/Projects/siowadou3/teibou_list/todoufuken.csv'
INTO TABLE todoufuken
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(id, name);
