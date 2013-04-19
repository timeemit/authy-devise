class Devise::DeviseAuthyController < DeviseController
  prepend_before_filter :find_resource_and_require_password_checked, :only => [
    :GET_verify_authy, :POST_verify_authy
  ]
  prepend_before_filter :authenticate_scope!, :only => [
    :GET_enable_authy, :POST_enable_authy,
    :GET_verify_authy_installation, :POST_verify_authy_installation
  ]
  include Devise::Controllers::Helpers

  def remember_device
    cookies.signed[:remember_device] = {
      :value => Time.now.to_i,
      :secure => !(Rails.env.test? || Rails.env.development?)
    }
  end

  def GET_verify_authy
    @authy_id = @resource.authy_id
    render :verify_authy
  end

  # verify 2fa
  def POST_verify_authy
    token = Authy::API.verify({
      :id => @resource.authy_id,
      :token => params[:token],
      :force => true
    })

    if token.ok?
      @resource.update_attribute(:last_sign_in_with_authy, DateTime.now)

      remember_device if params[:remember_device].to_i == 1

      set_flash_message(:notice, :signed_in) if is_navigational_format?
      sign_in(resource_name, @resource)
      respond_with resource, :location => after_sign_in_path_for(@resource)
    else
      render :verify_authy
    end
  end

  # enable 2fa
  def GET_enable_authy
    render :enable_authy
  end

  def POST_enable_authy
    @authy_user = Authy::API.register_user(
      :email => resource.email,
      :cellphone => params[:cellphone],
      :country_code => params[:country_code]
    )

    if @authy_user.ok?
      resource.authy_id = @authy_user.id
      if resource.save
        set_flash_message(:notice, :enabled)
      else
        set_flash_message(:error, :not_enabled)
        redirect_to :root and return
      end

      redirect_to [resource_name, :verify_authy_installation]
    else
      set_flash_message(:error, :not_enabled)
      render :enable_authy
    end
  end

  def GET_verify_authy_installation
    render :verify_authy_installation
  end

  def POST_verify_authy_installation
    token = Authy::API.verify({
      :id => self.resource.authy_id,
      :token => params[:token],
      :force => true
    })

    self.resource.authy_enabled = token.ok?
    if !token.ok? || !self.resource.save
      set_flash_message(:error, :not_enabled)
      render :verify_authy_installation
    else
      set_flash_message(:notice, :enabled)
      redirect_to :root
    end
  end

  def request_sms
    @resource = resource_class.find_by_id(session["#{resource_name}_id"])
    if !@resource
      render :json => {:sent => false, :message => "User couldn't be found."}
      return
    end

    response = Authy::API.request_sms(:id => @resource.id, :force => true)
    render :json => {:sent => response.ok?, :message => response.message}
  end

  private

  def authenticate_scope!
    send(:"authenticate_#{resource_name}!", :force => true)
    self.resource = send("current_#{resource_name}")
  end

  def find_resource_and_require_password_checked
    @resource = resource_class.find_by_id(session["#{resource_name}_id"])

    if @resource.nil? || session[:"#{resource_name}_password_checked"].to_s != "true"
      redirect_to :root
    end
  end
end
