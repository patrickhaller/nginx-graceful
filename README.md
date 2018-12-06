### Restart nginx without downtime

Usage: graceful.sh [ HOST | '' ]

As per [the docs](https://www.nginx.com/resources/wiki/start/topics/tutorials/commandline/), 
spawn a new nginx master process and workers, then quiesce the old workers.

The script will prompt for a commit or rollback;
at this point, test to verify that the new workers are handling correctly.

Provided that all is well, type "commit".
Any other response will rollback to the old master.

