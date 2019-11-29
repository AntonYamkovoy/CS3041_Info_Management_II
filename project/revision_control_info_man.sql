-- If creating this project in mySQL workbench
-- version must be over mysql 8.0 to use tree functionality

-- database schema must be called 'version_control' for triggers to work and be added


CREATE TABLE Organisation(
org_id Integer not null,
org_name varchar(30) not null,
created_at datetime not null DEFAULT NOW(),
billing_email varchar(40) not null,
descript varchar(140) not null,
PRIMARY KEY (org_id)
);





CREATE TABLE User(
user_id Integer not null,
login varchar(20) not null,
email VARCHAR(40) not null,
nickname VARCHAR(20) null, 
avatar_url varchar(100),
location VARCHAR(30),
org_id Integer,
deleted boolean not null DEFAULT false,
PRIMARY KEY (user_id), -- add unique constraint for login
FOREIGN KEY (org_id) REFERENCES Organisation(org_id)
ON DELETE RESTRICT
ON UPDATE CASCADE,
CONSTRAINT UC_Login UNIQUE (login)
);



CREATE TABLE Commit (
commit_id Integer not null,
sha varchar(50) not null,
commit_date datetime not null DEFAULT NOW(),
additions int not null DEFAULT 0, 
deletions int not null DEFAULT 0, 
total int not null DEFAULT 0, 
contents varchar(140) not null,
author_id Integer not null,
PRIMARY KEY (commit_id), -- add unique constraint for "sha"
FOREIGN KEY (author_id) REFERENCES User(user_id)
ON DELETE RESTRICT
 ON UPDATE CASCADE,
CONSTRAINT UC_commit_sha UNIQUE (sha)

);

CREATE TABLE Repository(
repo_id Integer not null,
repo_name varchar(20) not null,
descript varchar(140) not null,
url varchar(50) not null,
initial_commit_id Integer,
PRIMARY KEY (repo_id),
FOREIGN KEY (initial_commit_id) REFERENCES Commit(commit_id)
ON DELETE SET NULL
ON UPDATE CASCADE
);



CREATE TABLE PullRequest(
pr_id Integer not null,
created_by_id Integer not null,
content VARCHAR(140) not null,
assignee_id Integer,
closed_at datetime null,
created_at datetime not null DEFAULT NOW(),
repository_id Integer not null,
PRIMARY KEY (pr_id),
FOREIGN KEY (assignee_id) REFERENCES User(user_id)
ON DELETE RESTRICT
ON UPDATE CASCADE,
FOREIGN KEY (repository_id) REFERENCES Repository(repo_id)
ON DELETE RESTRICT
ON UPDATE CASCADE,
FOREIGN KEY (created_by_id) REFERENCES User(user_id)
ON DELETE RESTRICT
ON UPDATE CASCADE

);


CREATE TABLE Follow(
being_followed_id Integer not null,
following_id Integer not null,
PRIMARY KEY (being_followed_id,following_id),
FOREIGN KEY (being_followed_id) REFERENCES User(user_id)
ON DELETE RESTRICT
ON UPDATE CASCADE,
FOREIGN KEY (following_id) REFERENCES User(user_id)
ON DELETE RESTRICT
ON UPDATE CASCADE
);

CREATE TABLE Issue(
issue_id Integer not null,
descript VARCHAR(140) not null,
assignee_id Integer,
closed_at datetime,
created_by_id Integer,
created_at datetime DEFAULT NOW(),
closed_by_id Integer,
repository_id Integer not null,
PRIMARY KEY (issue_id),
FOREIGN KEY (assignee_id) REFERENCES User(user_id)
ON DELETE RESTRICT
ON UPDATE CASCADE,
FOREIGN KEY (closed_by_id) REFERENCES User(user_id)
ON DELETE RESTRICT
ON UPDATE CASCADE,
FOREIGN KEY (created_by_id) REFERENCES User(user_id)
ON DELETE RESTRICT
ON UPDATE CASCADE
);


CREATE TABLE Comment(
comment_id Integer not null,
commit_id Integer not null,
author_id Integer not null,
date_posted datetime not null DEFAULT NOW(),
contents varchar(140) not null,
PRIMARY KEY (comment_id),
FOREIGN KEY (author_id) REFERENCES User(user_id)
ON DELETE RESTRICT
ON UPDATE CASCADE,
FOREIGN KEY (commit_id) REFERENCES Commit(commit_id)
ON DELETE CASCADE
ON UPDATE CASCADE
);


CREATE TABLE Repo_User(
repo_id Integer not null,
contributor_id Integer not null,
PRIMARY KEY (repo_id,contributor_id),
FOREIGN KEY (repo_id) REFERENCES Repository(repo_id)
ON DELETE RESTRICT
ON UPDATE CASCADE,
FOREIGN KEY (contributor_id) REFERENCES User(user_id)
ON DELETE RESTRICT
ON UPDATE CASCADE

);


CREATE TABLE Branch (
branch_id Integer not null,
branch_name varchar(20) not null,
creation_date datetime not null DEFAULT NOW(),
PRIMARY KEY (branch_id)
);

CREATE TABLE StateChange (
state_change_id Integer not null,
end_state_commit_id Integer not null,
start_state_commit_id Integer not null,
link_branch_id Integer not null,
PRIMARY KEY (state_change_id),
FOREIGN KEY (end_state_commit_id) REFERENCES Commit(commit_id)
ON DELETE CASCADE
ON UPDATE CASCADE,
FOREIGN KEY (start_state_commit_id) REFERENCES Commit(commit_id)
ON DELETE RESTRICT
ON UPDATE CASCADE,
FOREIGN KEY (link_branch_id) REFERENCES Branch(branch_id)
ON DELETE RESTRICT
ON UPDATE CASCADE

);


CREATE TABLE File(
file_id Integer not null,
size Integer not null,
file_path varchar(50) not null,
PRIMARY KEY (file_id)
);

CREATE TABLE FileChange (
file_change_id Integer not null,
change_type Integer not null,
changed_file_id Integer not null,
commit_id Integer not null,
lines_count Integer not null,
PRIMARY KEY(file_change_id),
FOREIGN KEY (changed_file_id) REFERENCES file(file_id)
 ON DELETE CASCADE
 ON UPDATE CASCADE,
FOREIGN KEY (commit_id) REFERENCES Commit(commit_id)
 ON DELETE CASCADE
 ON UPDATE CASCADE,
CONSTRAINT CHK_change_type CHECK (change_type >= -1 AND change_type <= 1)
);


DROP TRIGGER IF EXISTS `version_control`.`user_BEFORE_DELETE`;
--  trigger to check that a user cannot be deleted sets the deleted field to true 
DELIMITER $$
USE `version_control`$$
CREATE DEFINER = CURRENT_USER TRIGGER `version_control`.`user_BEFORE_DELETE` BEFORE DELETE ON `user` FOR EACH ROW
BEGIN
	SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'table User does not support deletion';
END$$
DELIMITER ;
       

DROP TRIGGER IF EXISTS `version_control`.`on_closed_issue_delete`;
 -- trigger to check that an issue can only be deleted if it's open 
DELIMITER $$
USE `version_control`$$
CREATE DEFINER = CURRENT_USER TRIGGER `version_control`.`on_closed_issue_delete` BEFORE DELETE ON `issue` FOR EACH ROW
BEGIN
	IF (OLD.closed_by_id IS NOT NULL) THEN			
		SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Deletion of closed Issues is not allowed';
	END IF;
END$$
DELIMITER ;

DROP TRIGGER IF EXISTS `version_control`.`commit_deletion_trigger`;
 -- trigger to check that an commit can only be deleted if it's last int he tree 
DELIMITER $$
USE `version_control`$$
CREATE DEFINER = CURRENT_USER TRIGGER `version_control`.`commit_deletion_trigger` BEFORE DELETE ON `commit` FOR EACH ROW
BEGIN
		IF EXISTS (
			SELECT start_state_commit_id FROM StateChange 
            WHERE OLD.commit_id = end_state_commit_id        
        )
        THEN
        	SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Deletion of closed commits is not allowed';
		END IF;
END$$
DELIMITER ;



DROP TRIGGER IF EXISTS `version_control`.`commit_update_trigger_on_file_change_insert`;
 -- trigger to add deletions or additions when adding new fileChanges are created in commit 
DELIMITER $$
USE `version_control`$$
CREATE DEFINER = CURRENT_USER TRIGGER `version_control`.`commit_update_trigger_on_file_change_insert` AFTER INSERT ON `filechange`  FOR EACH ROW
BEGIN
    IF(NEW.change_type < 0) THEN
		UPDATE Commit SET deletions = NEW.lines_count  WHERE commit_id = NEW.commit_id;
	END IF;
	IF(NEW.change_type > 0) THEN
   		UPDATE Commit SET additions = NEW.lines_count  WHERE commit_id = NEW.commit_id;
	END IF;
END$$
DELIMITER ;



DROP TRIGGER IF EXISTS `version_control`.`commit_update_trigger_on_file_change_delete`;
 -- trigger to update deletions or additions when deleting fileChanges are created in commit 
DELIMITER $$
USE `version_control`$$
CREATE DEFINER = CURRENT_USER TRIGGER `version_control`.`commit_update_trigger_on_file_change_delete` AFTER INSERT ON `filechange`  FOR EACH ROW
BEGIN
    IF(NEW.change_type < 0) THEN
		UPDATE Commit SET deletions = (SELECT deletions FROM (SELECT * FROM Commit) as commits WHERE commit_id = NEW.commit_id) - NEW.lines_count  WHERE commit_id = NEW.commit_id;
	END IF;
	IF(NEW.change_type > 0) THEN
   		UPDATE Commit SET additions = (SELECT additions FROM  (SELECT * FROM Commit) as commits WHERE commit_id = NEW.commit_id) - NEW.lines_count  WHERE commit_id = NEW.commit_id;    
	END IF;
END$$
DELIMITER ;

DROP TRIGGER IF EXISTS `version_control`.`commit_update_trigger_on_file_change_update`;
 -- trigger to update deletions or additions when deleting fileChanges are created in commit  
DELIMITER $$
USE `version_control`$$
CREATE DEFINER = CURRENT_USER TRIGGER `version_control`.`commit_update_trigger_on_file_change_update` AFTER UPDATE ON `filechange`  FOR EACH ROW
BEGIN
    IF(NEW.change_type < 0) THEN
		UPDATE Commit SET deletions = (SELECT deletions FROM Commit WHERE commit_id = NEW.commit_id) + NEW.lines_count - OLD.lines_count  WHERE commit_id = NEW.commit_id;
	END IF;
	IF(NEW.change_type > 0) THEN
   		UPDATE Commit SET additions = (SELECT additions FROM Commit WHERE commit_id = NEW.commit_id) + NEW.lines_count  - OLD.lines_count WHERE commit_id = NEW.commit_id;    
	END IF;
END$$
DELIMITER ;


CREATE VIEW Followers_view AS
SELECT u1.login AS Followed, u2.login AS Follower
FROM Follow f 
INNER JOIN  User u1 ON f.being_followed_id = u1.user_id 
INNER JOIN  User u2 ON f.following_id = u2.user_id;

-- Supported only starting from MySql 8.0.1
-- gets all the children in the commit tree of a given commit id
CREATE PROCEDURE get_all_children(IN parent_id integer)
with recursive cte (end_state_commit_id, branch_id, start_state_commit_id) 
as (
  select     end_state_commit_id,
			 link_branch_id,
             start_state_commit_id
  from       StateChange
  where      start_state_commit_id = parent_id
  union all
  select     p.end_state_commit_id,
             p.link_branch_id,
             p.start_state_commit_id
  from       StateChange p
  inner join cte
          on p.start_state_commit_id = cte.end_state_commit_id
)
select end_state_commit_id, branch_id, start_state_commit_id from cte ;



INSERT INTO Organisation (org_id,org_name,created_at,billing_email,descript)
VALUES (1,'anton_org',NOW(),'yamkovoa@tcd.ie','anton organisation');

INSERT INTO Organisation (org_id,org_name,created_at,billing_email,descript)
VALUES (2,'kamil_org',NOW(),'kamilprz@tcd.ie','kamil organisation');


INSERT INTO User(user_id,login,email,nickname,avatar_url,location,org_id) 
VALUES (1,'AntonYamkovoy','yamkovoa@tcd.ie','Anton','image_anton','Dublin',1);

INSERT INTO User(user_id,login,email,nickname,avatar_url,location,org_id) 
VALUES (2,'KamilPrz','kamilprz@tcd.ie','Kamil','image_kamil','Dublin',2);

INSERT INTO User(user_id,login,email,nickname,avatar_url,location,org_id) 
VALUES (3,'AndreyYamkovoy','andrey@tcd.ie','Andrey','image_andrey','Dublin',1);

INSERT INTO User(user_id,login,email,nickname,avatar_url,location) 
VALUES (4,'yungene','eugene@tcd.ie','Eugene','image_eugene','Dublin');

INSERT INTO COMMIT(commit_id,sha,additions,deletions,total,contents,author_id)
VALUES (1,'0001A',5,3,2,'first commit anton',1);

INSERT INTO COMMIT(commit_id,sha,additions,deletions,total,contents,author_id)
VALUES (2,'0001B',10,3,7,'first commit kamil',2);

INSERT INTO COMMIT(commit_id,sha,additions,deletions,total,contents,author_id)
VALUES (3,'0001C',50,50,0,'first commit andrey',3);

INSERT INTO COMMIT(commit_id,sha,additions,deletions,total,contents,author_id)
VALUES (4,'0001D',90,40,50,'second commit kamil',2);

INSERT INTO COMMIT(commit_id,sha,additions,deletions,total,contents,author_id)
VALUES (5,'0001E',5,10,-5,'third commit kamil',2);

INSERT INTO COMMIT(commit_id,sha,additions,deletions,total,contents,author_id)
VALUES (6,'0001F',10,12,-2,'second commit anton',1);

INSERT INTO COMMIT(commit_id,sha,additions,deletions,total,contents,author_id)
VALUES (7,'0001G',5,3,2,'second commit andrey',3);

INSERT INTO COMMIT(commit_id,sha,additions,deletions,total,contents,author_id)
VALUES (8,'0001H',1,1,0,'third commit anton',1);

INSERT INTO COMMIT(commit_id,sha,additions,deletions,total,contents,author_id)
VALUES (9,'0001I',52,3,49,'third commit andrey',3);

INSERT INTO COMMIT(commit_id,sha,additions,deletions,total,contents,author_id)
VALUES (10,'0001J',1,3,-2,'fourth commit anton',1);

INSERT INTO COMMIT(commit_id,sha,additions,deletions,total,contents,author_id)
VALUES (11,'0001K',10,5,5,'first commit eugene',4);

INSERT INTO COMMIT(commit_id,sha,additions,deletions,total,contents,author_id)
VALUES (12,'0001L',20,1,19,'second commit eugene',4);

INSERT INTO Repository(repo_id,repo_name,descript,url,initial_commit_id)
VALUES (1,'repo1','Anton Kamil Andrey repo','github/repo1',1);

INSERT INTO Repository(repo_id,repo_name,descript,url,initial_commit_id)
VALUES (2,'repo2','Eugene repo','github/repo2',11);

INSERT INTO PullRequest(pr_id,created_by_id,content,repository_id)
VALUES (1,3,'andreys pull request 1',1);

INSERT INTO PullRequest(pr_id,created_by_id,content,repository_id)
VALUES (2,4,'eugenes pull request 1',2);

INSERT INTO Follow(being_followed_id,following_id)
VALUES (1,2); -- kamil following anton

INSERT INTO Follow(being_followed_id,following_id)
VALUES (1,3); -- andrey following anton

INSERT INTO Follow(being_followed_id,following_id)
VALUES (1,4); -- yungene following anton

INSERT INTO Follow(being_followed_id,following_id)
VALUES (2,4); -- yungene following kamil

INSERT INTO Follow(being_followed_id,following_id)
VALUES (2,1); -- anton following kamil

INSERT INTO Follow(being_followed_id,following_id)
VALUES (4,1); -- anton following yungene

INSERT INTO Follow(being_followed_id,following_id)
VALUES (4,2); -- kamil following yungene

INSERT INTO Issue(issue_id,descript,created_by_id,repository_id)
VALUES (1,'anton issue in repo1', 1,1);

INSERT INTO Issue(issue_id,descript,created_by_id,repository_id)
VALUES (2,'eugene issue in repo2', 4,2);

INSERT INTO Comment(comment_id,commit_id,author_id,contents)
VALUES (1,10,1,'anton comment on commit 10');

INSERT INTO Comment(comment_id,commit_id,author_id,contents)
VALUES (2,2,2,'kamil comment on commit 2');


INSERT INTO Comment(comment_id,commit_id,author_id,contents)
VALUES (3,11,4,'eugene comment on commit 11');

INSERT INTO Comment(comment_id,commit_id,author_id,contents)
VALUES (4,12,4,'eugene comment on commit 12');


INSERT INTO Repo_User(repo_id,contributor_id)
VALUES (1,1); -- anton in repo 1

INSERT INTO Repo_User(repo_id,contributor_id)
VALUES (1,2); -- kamil in repo 1

INSERT INTO Repo_User(repo_id,contributor_id)
VALUES (1,3); -- andrey in repo 1

INSERT INTO Repo_User(repo_id,contributor_id)
VALUES (2,4); -- eugene in repo 2



INSERT INTO Branch(branch_id,branch_name)
VALUES (1,'repo1 master');

INSERT INTO Branch(branch_id,branch_name)
VALUES (2,'repo1 branch1');

INSERT INTO Branch(branch_id,branch_name)
VALUES (3,'repo1 branch2');

INSERT INTO Branch(branch_id,branch_name)
VALUES (4,'repo2 master');



-- master branch in repo1
INSERT INTO StateChange(state_change_id,end_state_commit_id,start_state_commit_id,link_branch_id)
VALUES (1,1,2,1);

INSERT INTO StateChange(state_change_id,end_state_commit_id,start_state_commit_id,link_branch_id)
VALUES (2,2,3,1);

INSERT INTO StateChange(state_change_id,end_state_commit_id,start_state_commit_id,link_branch_id)
VALUES (3,3,6,1);

INSERT INTO StateChange(state_change_id,end_state_commit_id,start_state_commit_id,link_branch_id)
VALUES (4,6,9,1);

-- branch1 in repo1

INSERT INTO StateChange(state_change_id,end_state_commit_id,start_state_commit_id,link_branch_id)
VALUES (5,2,4,2);

INSERT INTO StateChange(state_change_id,end_state_commit_id,start_state_commit_id,link_branch_id)
VALUES (6,4,5,2);

INSERT INTO StateChange(state_change_id,end_state_commit_id,start_state_commit_id,link_branch_id)
VALUES (7,5,7,2);

-- branch2 in repo1

INSERT INTO StateChange(state_change_id,end_state_commit_id,start_state_commit_id,link_branch_id)
VALUES (8,5,8,3);

INSERT INTO StateChange(state_change_id,end_state_commit_id,start_state_commit_id,link_branch_id)
VALUES (9,8,10,3);

-- master in repo2

INSERT INTO StateChange(state_change_id,end_state_commit_id,start_state_commit_id,link_branch_id)
VALUES (10,11,12,4);

INSERT INTO File(file_id,size,file_path)
VALUES (1,10,'file1');

INSERT INTO File(file_id,size,file_path)
VALUES (2,100,'file2');

INSERT INTO File(file_id,size,file_path)
VALUES (3,50,'file3');

INSERT INTO File(file_id,size,file_path)
VALUES (4,12,'file4');

INSERT INTO File(file_id,size,file_path)
VALUES (5,100,'file5');

INSERT INTO File(file_id,size,file_path)
VALUES (6,50,'file6');

INSERT INTO File(file_id,size,file_path)
VALUES (7,12,'file7');

INSERT INTO File(file_id,size,file_path)
VALUES (8,100,'file8');

INSERT INTO File(file_id,size,file_path)
VALUES (9,50,'file9');

INSERT INTO File(file_id,size,file_path)
VALUES (10,4,'file10');

INSERT INTO File(file_id,size,file_path)
VALUES (11,90,'file11');

INSERT INTO File(file_id,size,file_path)
VALUES (12,60,'file12');

INSERT INTO File(file_id,size,file_path)
VALUES (13,15,'file13');

INSERT INTO File(file_id,size,file_path)
VALUES (14,100,'file14');

INSERT INTO File(file_id,size,file_path)
VALUES (15,50,'file15');

INSERT INTO File(file_id,size,file_path)
VALUES (16,12,'file16');



INSERT INTO FileChange(file_change_id,change_type,changed_file_id,commit_id,lines_count)
VALUES (1,1,1,1,5);

INSERT INTO FileChange(file_change_id,change_type,changed_file_id,commit_id,lines_count)
VALUES (2,-1,2,2,10);

INSERT INTO FileChange(file_change_id,change_type,changed_file_id,commit_id,lines_count)
VALUES (3,1,3,3,50);

INSERT INTO FileChange(file_change_id,change_type,changed_file_id,commit_id,lines_count)
VALUES (4,-1,4,4,12);

INSERT INTO FileChange(file_change_id,change_type,changed_file_id,commit_id,lines_count)
VALUES (5,-1,5,4,10);

INSERT INTO FileChange(file_change_id,change_type,changed_file_id,commit_id,lines_count)
VALUES (6,1,6,5,100);

INSERT INTO FileChange(file_change_id,change_type,changed_file_id,commit_id,lines_count)
VALUES (7,1,7,5,11);

INSERT INTO FileChange(file_change_id,change_type,changed_file_id,commit_id,lines_count)
VALUES (8,-1,8,7,20);

INSERT INTO FileChange(file_change_id,change_type,changed_file_id,commit_id,lines_count)
VALUES (9,1,9,10,30);

INSERT INTO FileChange(file_change_id,change_type,changed_file_id,commit_id,lines_count)
VALUES (10,1,10,6,20);

INSERT INTO FileChange(file_change_id,change_type,changed_file_id,commit_id,lines_count)
VALUES (11,1,11,9,20);

INSERT INTO FileChange(file_change_id,change_type,changed_file_id,commit_id,lines_count)
VALUES (12,1,12,9,50);

INSERT INTO FileChange(file_change_id,change_type,changed_file_id,commit_id,lines_count)
VALUES (13,1,13,11,20);

INSERT INTO FileChange(file_change_id,change_type,changed_file_id,commit_id,lines_count)
VALUES (14,1,14,11,90);

INSERT INTO FileChange(file_change_id,change_type,changed_file_id,commit_id,lines_count)
VALUES (15,-1,15,11,20);

INSERT INTO FileChange(file_change_id,change_type,changed_file_id,commit_id,lines_count)
VALUES (16,1,16,12,40);








