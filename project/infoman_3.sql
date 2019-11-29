-- SELECT * FROM Commit WHERE author_id = 2
-- Example query of getting all commits of a given user


-- SELECT * FROM User WHERE user_id  IN (SELECT contributor_id FROM Repo_User WHERE repo_id = 1)
 -- Example query to get all the users in a specific repository
 
  SELECT * FROM User WHERE user_id  IN (SELECT author_id FROM Comment)
 -- Example query : getting all users who post comments
 
 