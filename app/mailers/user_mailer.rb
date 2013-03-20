class UserMailer < ActionMailer::Base
  default from: "support@halfpastnow.com"

  def welcome_email(user)
  	puts "sending email..."
    @user = user
    @url  = "http://halfpastnow.com/login"
    mail(:to => user.email, :subject => "Welcome to halfpastnow!")
  end
  def weekly_email(user)
  	puts "sending email..."
    @user = user
    @url  = "http://halfpastnow.com/login"
    mail(:to => user.email, :subject => "This week in halfpastnow!")
  end
  
end
