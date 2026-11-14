-- These queries should all pass levels 1-5

-- Simple select with known columns
SELECT id, username, email FROM users WHERE id = $1;

-- Join with qualified column references
SELECT p.title, u.username FROM posts p JOIN users u ON p.author_id = u.id WHERE p.published = true;

-- Parameterised insert (injection-safe)
INSERT INTO comments (post_id, user_id, body) VALUES ($1, $2, $3);

-- Type-compatible comparison: integer = integer
SELECT id, title FROM posts WHERE author_id = $1 AND published = true;
