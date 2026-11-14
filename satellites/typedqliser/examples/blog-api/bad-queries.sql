-- These queries should FAIL at various levels

-- Level 1 failure: syntax error
SELEC * FORM users;

-- Level 2 failure: nonexistent table
SELECT * FROM nonexistent_table WHERE id = 1;

-- Level 2 failure: nonexistent column
SELECT id, full_name FROM users;

-- Level 3 failure: comparing string to integer
SELECT id FROM posts WHERE author_id = 'not_a_number';
