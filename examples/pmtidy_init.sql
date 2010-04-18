DROP TABLE IF EXISTS pmtidy;

CREATE TABLE pmtidy (
    md5        BINARY(16) PRIMARY KEY,
    tidytype   TINYINT NOT NULL,
    codetext   TEXT NOT NULL,
    created    TIMESTAMP DEFAULT NOW()
);
