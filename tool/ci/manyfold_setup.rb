# Prepares a throwaway Manyfold for the contract tests: an owner, the library
# the workflow copied into /libraries, and the OAuth application Bambuddy
# signs in with. Run with `bin/rails runner` inside the manyfold-solo
# container; prints CLIENT_ID= and CLIENT_SECRET= for the workflow to read.

owner = User.find_by(username: "contract") || User.create!(
  username: "contract",
  email: "contract@example.invalid",
  password: "Contract-owner-1",
  password_confirmation: "Contract-owner-1"
)

library = Library.find_by(path: "/libraries") ||
  Library.create!(path: "/libraries", name: "contract")
Scan::Library::DetectFilesystemChangesJob.perform_now(library.id)

# The scan only enqueues the model; Sidekiq builds it a moment later, and a
# test that lists models before then sees an empty library.
60.times do
  break if Model.any? && ModelFile.any?
  sleep 1
end
abort "Manyfold indexed no model from /libraries" unless Model.any?

app = Doorkeeper::Application.find_by(name: "bambuddy-contract") ||
  Doorkeeper::Application.create!(
    name: "bambuddy-contract",
    redirect_uri: "urn:ietf:wg:oauth:2.0:oob",
    scopes: "public read",
    confidential: true,
    owner: owner
  )
puts "CLIENT_ID=#{app.uid}"
puts "CLIENT_SECRET=#{app.plaintext_secret || app.secret}"
