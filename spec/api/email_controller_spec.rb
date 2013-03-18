require 'spec_helper'

include WebMock::API
include Hermes

describe Hermes::V1::MessagesController do

  include Rack::Test::Methods

  before :each do
    Hermes::Configuration.instance.load!(File.expand_path('../..', __FILE__))
  end

  def app
    Hermes::V1::MessagesController
  end

  describe " > Email functions > " do
    describe "POST /:realm/messages/email" do
      it 'accepts message' do
        stub_mailgun_post!
        post "/test/messages/email", {
          :recipient_email => 'test@test.com',
          :subject => "Foo",
          :text => 'Yip',
          :html => '<p>Yip</p>'
        }
        stub_mailgun_post!.should have_been_requested
        last_response.status.should eq 200
        stub_grove_post!.should have_been_requested
      end
    end
  end
end
