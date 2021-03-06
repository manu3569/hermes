require 'spec_helper'

include WebMock::API
include Hermes

describe 'Receiving' do

  def app
    Hermes::V1
  end

  let :realm do
    Realm.new('test', {
      session: 'some_checkpoint_god_session_for_test_realm',
      host: {'test' => 'example.org'},
      grove_path: 'boink',
      incoming_url: 'http://example.org/incoming',
      implementations: {
        sms: {
          provider: 'Null'
        },
        email: {
          provider: 'Null'
        }
      }
    })
  end

  before :each do
    Configuration.instance.add_realm('test', realm)
  end

  describe "POST /:realm/incoming/sms" do

    [true, false].each do |acking|
      context "when provider #{acking ? 'acks' : 'does not ack'}" do
        it 'it receives the message, stores it and performs callback' do
          Providers::NullProvider.any_instance.
            should_receive(:parse_message) { |request|
              request.env['rack.input'].read.should eq "<something></something>"
            }.once.and_return({
              recipient_number: '12345678',
              text: 'Hello',
              id: "666",
              some_extra_data: "Yikes"
            })

          if acking
            Providers::NullProvider.any_instance.
              should_receive(:ack_message) { |message, controller|
                controller.success! status: 201, message: "OK"
              }.
              with(
                hash_including(
                  recipient_number: '12345678',
                  text: 'Hello',
                  id: "666",
                  some_extra_data: "Yikes"),
                an_instance_of(::Hermes::V1)
              ).
              once
          end

          grove_post_stub = stub_request(:post, "http://example.org/api/grove/v1/posts/post.hermes_message:test.boink").
            with(
              body: {
                session: "some_checkpoint_god_session_for_test_realm",
                post: {
                  document: {
                    recipient_number: "12345678",
                    text: "Hello",
                    kind: "sms",
                    some_extra_data: "Yikes",
                    id: "666"
                  },
                  external_id: "null_provider_id:666",
                  restricted: true,
                  tags: ["received"]
                }
              },
              headers: {
                'Accept' => 'application/json',
                'Content-Type' => 'application/json'
              }
            ).
            to_return(
              status: 200,
              body: {
                post: {
                  uid: "post.hermes_message:test.boink$1234",
                  document: {
                    body: "Hello",
                  },
                  tags: ["received"]
                }
              }.to_json)

          callback_stub = stub_request(:post, "http://example.org/incoming").
            with(
              query: {
                uid: "post.hermes_message:test.boink$1234"
              }
            ).to_return(
              status: 200,
              body: "")

          post_body "/test/incoming/sms", {}, %{<something></something>}
          if acking
            expect(last_response.status).to eq 201
            expect(last_response.body).to eq 'OK'
          else
            expect(last_response.status).to eq 200
            expect(last_response.body).to eq 'Received'
          end
          expect(last_response).to have_media_type('text/plain')

          callback_stub.should have_been_requested
        end
      end
    end

    it 'it converts binary data to Base64' do
      Providers::NullProvider.any_instance.
        should_receive(:parse_message).once.and_return({
          recipient_number: '12345678',
          binary: {
            value: 'HELLO',
            content_type: 'application/octet-stream',
            transfer_encoding: :raw
          },
          id: "666"
        })

      grove_post_stub = stub_request(:post, "http://example.org/api/grove/v1/posts/post.hermes_message:test.boink").
        with(
          body: {
            session: "some_checkpoint_god_session_for_test_realm",
            post: {
              document: {
                recipient_number: "12345678",
                binary: {
                  value: Base64.encode64('HELLO'),
                  content_type: 'application/octet-stream',
                  transfer_encoding: 'base64'
                },
                kind: "sms",
                id: "666"
              },
              external_id: "null_provider_id:666",
              restricted: true,
              tags: ["received"]
            }
          },
          headers: {
            'Accept' => 'application/json',
            'Content-Type' => 'application/json'
          }
        ).
        to_return(
          status: 200,
          body: {
            post: {
              uid: "post.hermes_message:test.boink$1234",
              document: {
                body: "Hello",
              },
              tags: ["received"]
            }
          }.to_json)

      callback_stub = stub_request(:post, "http://example.org/incoming").
        with(
          query: {
            uid: "post.hermes_message:test.boink$1234"
          }
        ).to_return(
          status: 200,
          body: "")

      post_body "/test/incoming/sms", {}, %{<something></something>}
      expect(last_response.status).to eq 200
      expect(last_response).to have_media_type('text/plain')

      callback_stub.should have_been_requested
    end

    it 'it rejects incomplete message' do
      Providers::NullProvider.any_instance.
        should_receive(:parse_message).once.and_raise(Hermes::InvalidMessageError)

      post_body "/test/incoming/sms", {}, %{<something></something>}
      expect(last_response.status).to eq 400
      expect(last_response).to have_media_type('text/plain')
    end

  end

  describe "POST /:realm/incoming/email" do

    [true, false].each do |acking|
      context "when provider #{acking ? 'acks' : 'does not ack'}" do
        it 'it receives the message, stores it and performs callback' do
          Providers::NullProvider.any_instance.
            should_receive(:parse_message) { |request|
              request.env['rack.input'].read.should eq "<something></something>"
            }.once.and_return({
              recipient_email: 'bob@example.com',
              text: 'Hello',
              id: "666"
            })

          if acking
            Providers::NullProvider.any_instance.
              should_receive(:ack_message) { |message, controller|
                controller.success! status: 201, message: "OK"
              }.
              with(
                hash_including(
                  recipient_email: 'bob@example.com',
                  text: 'Hello',
                  id: "666"),
                an_instance_of(::Hermes::V1)
              ).
              once
          end

          grove_post_stub = stub_request(:post, "http://example.org/api/grove/v1/posts/post.hermes_message:test.boink").
            with(
              body: {
                session: "some_checkpoint_god_session_for_test_realm",
                post: {
                  document: {
                    recipient_email: "bob@example.com",
                    text: "Hello",
                    kind: "email",
                    id: "666"
                  },
                  external_id: "null_provider_id:666",
                  restricted: true,
                  tags: ["received"]
                }
              },
              headers: {
                'Accept' => 'application/json',
                'Content-Type' => 'application/json'
              }
            ).
            to_return(
              status: 200,
              body: {
                post: {
                  uid: "post.hermes_message:test.boink$1234",
                  document: {
                    body: "Hello",
                  },
                  tags: ["received"]
                }
              }.to_json)

          callback_stub = stub_request(:post, "http://example.org/incoming").
            with(
              query: {
                uid: "post.hermes_message:test.boink$1234"
              }
            ).to_return(
              status: 200,
              body: "")

          post_body "/test/incoming/email", {}, %{<something></something>}
          if acking
            expect(last_response.status).to eq 201
            last_response.body.should eq 'OK'
          else
            expect(last_response.status).to eq 200
            last_response.body.should eq 'Received'
          end
          expect(last_response).to have_media_type('text/plain')

          callback_stub.should have_been_requested
        end
      end
    end

    it 'it rejects incomplete message' do
      Providers::NullProvider.any_instance.
        should_receive(:parse_message).once.and_raise(Hermes::InvalidMessageError)

      post_body "/test/incoming/email", {}, %{<something></something>}
      expect(last_response.status).to eq 400
      expect(last_response).to have_media_type('text/plain')
    end

  end

end
