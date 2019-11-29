USE `version_control`;
call get_all_children(10);
-- this query calls the defined stored procedure to get all the children of a recent commit in the commit tree of a repo
-- it returns all of the state change objects that define that commit tree, It will result in the whole tree from that child node, including all branches of the commit tree

