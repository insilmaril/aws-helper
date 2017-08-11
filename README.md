# aws-helper
Helper scripts for working with AWS using ruby and a local MUA (default: mutt) to send notification mails.

## aws-create-accounts.rb
Creates new user and sends credentials as email to new user. The notification mail is available as template, 
so also links to documentation can be passed along to reduce the need for support.

An existing user can be used as "template" user, groups for the new user will be copied from this template user.

Example:

     aws-create-accounts.rb -t user.existing -m new-user-email@company.com -u user.new

will result in 

     Existing users: 123
     Created: arn:aws:iam::419024239262:user/user.new
     Created password for user.new
     Created access keys for user.new
     Groups of user.new:
     Mailed credentials to new-user-email@company.com
