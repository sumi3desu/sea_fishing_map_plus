LOAD DATA LOCAL INFILE '/Users/bouzer/Projects/siowadou3/teibou_list/愛知県.csv'
INTO TABLE teibou
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(id, name, furigana, kubun, address, latitude, longitude, note);
