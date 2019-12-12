host=$1
[ -z "$host" ] && jekyll s --drafts --port 4001  --incremental
[ -n "$host" ] && jekyll s --drafts --host=$1 --port 4001  --incremental
