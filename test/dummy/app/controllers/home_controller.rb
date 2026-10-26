class HomeController < ApplicationController
  def show = render(plain: "host home")
  def about = render(plain: "host about")
  def account = render(plain: "host account")
end
