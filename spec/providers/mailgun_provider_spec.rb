# encoding: UTF-8
require 'spec_helper'

include Hermes::Providers
include WebMock::API

describe MailGunProvider do

  let :provider do
    MailGunProvider.new(api_key: 'foo', mailgun_domain: 'test.com')
  end

  describe "#initialize" do

    it 'can be configured with minimal configuration' do
      provider = MailGunProvider.new(api_key: 'foo', mailgun_domain: 'test.com')
      provider.api_key.should eq 'foo'
      provider.mailgun_domain.should eq 'test.com'
    end

    it 'requires API key' do
      -> {
        MailGunProvider.new
      }.should raise_error(ConfigurationError)
    end

    it 'raises ArgumentError on bad keys' do
      -> {
        MailGunProvider.new(subject: 'bar@foo.com')
      }.should raise_error(ArgumentError)
    end

  end

  describe "#send_message!" do

    it "posts message and returns ID" do
      stub_request(:post, "https://api:foo@api.mailgun.net/v2/test.com/messages").
        with(
          body: {
            from: "No-reply <no-reply@test.com>",
            html: "",
            subject: "",
            text: "test",
            to: "foo@bar.com"
          },
          headers: {
            'Authorization' => 'Basic YXBpOmZvbw==',
            'Content-Type' => 'application/x-www-form-urlencoded'
          }).
        to_return(
          status: 200,
          body: {
            message: "Queued. Thank you.",
            id: "<20111114174239.25659.5817@test.com>"
          }.to_json,
          headers: {})

      provider.send_message!(
        recipient_email: 'foo@bar.com', text: 'test').should eq "<20111114174239.25659.5817@test.com>"
    end

    it "translates error into RecipientRejectedError" do
      stub_request(:post, "https://api:foo@api.mailgun.net/v2/test.com/messages").
        to_return(
          status: 400,
          body: {
            message: "'to' parameter is not a valid address, you dick.",
          }.to_json)

      -> {
        provider.send_message!(
          recipient_email: 'foo@bar.com', text: 'test')
      }.should raise_error(RecipientRejectedError) { |e|
        e.recipient.should eq "foo@bar.com"
        e.reason.should eq "'to' parameter is not a valid address, you dick."
      }
    end

  end

  describe '#parse_receipt' do

    it "parses success" do
      result = provider.parse_receipt("/", {}, {"Message-Id" => "338166433", "event" => "delivered"})
      result[:id].should eq "338166433"
      result[:status].should == :delivered
    end

    it "parses failure" do
      result = provider.parse_receipt("/", {}, {"Message-Id" => "338166433", "event" => "dropped"})
      result[:id].should eq "338166433"
      result[:status].should == :failed
    end

    it "parses unknown" do
      result = provider.parse_receipt("/", {}, {"Message-Id" => "338166433", "event" => "fofofofo"})
      result[:id].should eq "338166433"
      result[:status].should == :unknown
    end

  end

end
