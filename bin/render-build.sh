#!/usr/bin/env bash
set -o errexit

bundle install
bin/rails assets:precompile
bin/rails assets:clean

# Keep migrations here if you're not using a pre-deploy command
bin/rails db:migrate