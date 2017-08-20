# TextRef

TextRef is the open source software behind the [textref.org](https://textref.org/) library catalog sharing website.

## Prerequisites
* Web server capable of running Perl code
* MySQL

## Installation

Make sure you have installed the following perl modules from CPAN:
* CGI
* DBI
* Encode
* Text::CSV

Next create a MySQL database for your installation, and a user account which can access this database.

Open the file TextRef/Setup.pm, and edit the connection string in the "dbiconnect" function to point to your database, account, and password.

From the console, run ```perl catalogupdateall.pl``` to update data for all catalogs specified in the Setup.pm file - when run for the first time, this will create the necessary database tables. If you want your catalog data to be updated automatically, you should also add an entry to run this script in ```/etc/crontab```.

With the files in an appropriate location for your webserver, your catalog system should then be accessible by visiting http://example.com/textref.pl.

## Licence

Copyright 2017 [Donald Sturgeon](https://dsturgeon.net/). Licensed under the GPL v2.0 - see the LICENSE file for details.
