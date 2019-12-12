#! /bin/bash

git add .
git commit -m 'rsync'
if [ -n "$2" ];then
	 git pull && git push
else
	git push
fi
