# -*- coding: UTF-8 -*-
#
# Copyright:: Copyright (c) 2014 Chef Software Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require "spec_helper"
require "chef-dk/policyfile_compiler"

describe ChefDK::PolicyfileCompiler, "including upstream policy locks" do

  def expand_run_list(r)
    r.map do |item|
      "recipe[#{item}]"
    end
  end

  let(:run_list) { ["local::default"] }
  let(:run_list_expanded) { expand_run_list(run_list) }
  let(:named_run_list) { {} }
  let(:named_run_list_expanded) do
    named_run_list.inject({}) do |acc, (key, val)|
      acc[key] = expand_run_list(val)
      acc
    end
  end

  let(:default_source) { nil }

  let(:external_cookbook_universe) {
    {
      "cookbookA" => {
        "1.0.0" => [ ],
        "2.0.0" => [ ],
      },
      "cookbookB" => {
        "1.0.0" => [ ],
        "2.0.0" => [ ],
      },
      "cookbookC" => {
        "1.0.0" => [ ],
        "2.0.0" => [ ],
      },
      "local" => {
        "1.0.0" => [ ["cookbookC", "= 1.0.0" ] ],
      },
      "local_easy" => {
        "1.0.0" => [ ["cookbookC", "= 2.0.0" ] ],
      }
    }
  }
  
  let(:included_policy_expanded_named_runlist) { nil }
  let(:included_policy_expanded_runlist) { ["recipe[cookbookA::default]"] }
  let(:included_policy_cookbooks) {
    [
      {
        name: "cookbookA",
        version: "2.0.0"
      }
    ]
  }

  let(:included_policy_lock_data) do
    cookbook_locks = included_policy_cookbooks.inject({}) do |acc, cookbook_info|
      acc[cookbook_info[:name]] = {
        "version" => cookbook_info[:version],
        "identifier" => "identifier",
        "dotted_decimal_identifier" => "dotted_decimal_identifier",
        "cache_key" => "#{cookbook_info[:name]}-#{cookbook_info[:version]}",
        "origin" => "uri",
        "source_options" => {}
      }
      acc
    end

    solution_dependencies_lock = included_policy_cookbooks.map do |cookbook_info|
      [cookbook_info[:name], cookbook_info[:version]]
    end

    {
      "name" => "included_policyfile",
      "revision_id" => "myrevisionid",
      "run_list" => included_policy_expanded_runlist,
      "cookbook_locks" => cookbook_locks,
      "default_attributes" => {},
      "override_attributes" => {},
      "solution_dependencies" => {
        "Policyfile"=> solution_dependencies_lock,
        ## We dont use dependencies, no need to fill it out
        "dependencies" => {}
      }
    }.tap do |core|
      core["named_run_lists"] = included_policy_expanded_named_runlist if included_policy_expanded_named_runlist 
    end
  end

  let(:included_policy_lock_name) { "included" }

  let(:included_policy_lock_spec) do
    ChefDK::Policyfile::PolicyfileLocationSpecification.new(included_policy_lock_name, {:local => "somelocation"}, nil).tap do |spec|
      allow(spec).to receive(:valid?).and_return(true)
      allow(spec).to receive(:ensure_cached)
      allow(spec).to receive(:lock_data).and_return(included_policy_lock_data)
    end
  end

  let (:included_policies) { [] }

  let(:policyfile) do
    policyfile = ChefDK::PolicyfileCompiler.new.build do |p|

      p.default_source.replace([default_source]) if default_source
      p.run_list(*run_list)
      named_run_list.each do |name, run_list|
        p.named_run_list(name, *run_list)
      end

      allow(p).to receive(:included_policies).and_return(included_policies)
      allow(p.default_source.first).to receive(:universe_graph).and_return(external_cookbook_universe)
    end

    policyfile
  end

  let(:policyfile_lock) do
    policyfile.lock
  end

  context "when no policies are included" do

    it "does not emit included policies information in the lockfile" do
      expect(policyfile_lock.to_lock["included_policies"]).to eq(nil)
    end

  end

  context "when one policy is included" do

    let(:included_policies) { [included_policy_lock_spec] }

    it "emits a lockfile describing the source of the included policy"

    # currently you must have a run list in a policyfile, but it should now
    # become possible to make a combo-policy just by combining other policies
    context "when the including policy does not have a run list" do
      let(:run_list) { [] }

      it "emits a lockfile with an identical run list as the included policy" do
        expect(policyfile_lock.to_lock["run_list"]).to eq(included_policy_expanded_runlist)
      end

    end

    context "when the including policy has a run list" do

      it "appends run list items from the including policy to the included policy's run list, removing duplicates" do
        expect(policyfile_lock.to_lock["run_list"]).to eq(included_policy_expanded_runlist + run_list_expanded)
      end

    end

    context "when the policies have named run lists" do

      let(:included_policy_expanded_named_runlist) do
        {
          "shared" => ["recipe[cookbookA::included]"]
        }
      end

      context "and no named run lists are shared between the including and included policy" do

        let(:named_run_list) do
          {
            "local" => ["local::foo"]
          }
        end

        it "preserves the named run lists as given in both policies" do
          expect(policyfile_lock.to_lock["named_run_lists"]).to include(included_policy_expanded_named_runlist, named_run_list_expanded)
        end

      end

      context "and some named run lists are shared between the including and included policy" do

        let(:named_run_list) do
          {
            "shared" => ["local::foo"]
          }
        end

        it "appends run lists items from the including policy's run lists to the included policy's run lists" do
          expect(policyfile_lock.to_lock["named_run_lists"]["shared"]).to eq(included_policy_expanded_named_runlist["shared"] + named_run_list_expanded["shared"])
        end

      end

    end

    context "when no cookbooks are shared as dependencies or transitive dependencies" do

      it "does not raise a have conflicting dependency requirements error"

      it "emits a lockfile where cookbooks pulled from the upstream are at identical versions"

      it "solves the dependencies added by the top-level policyfile and emits them in the lockfile"

    end

    context "when some cookbooks are shared as dependencies or transitive dependencies" do
      let(:included_policy_expanded_runlist) { ["recipe[cookbookC::default]"] }
      let(:included_policy_cookbooks) {
        [
          {
            name: "cookbookC",
            version: "2.0.0"
          }
        ]
      }

      context "and the including policy's dependencies can be solved with the included policy's locks" do
        let(:run_list) { ["local_easy::default"] }

        it "solves the dependencies added by the top-level policyfile and emits them in the lockfile" do
          expect(policyfile_lock.to_lock["solution_dependencies"]["dependencies"]).to(
            have_key("cookbookC (2.0.0)"))
        end

      end

      context "and the including policy's dependencies cannot be solved with the included policy's locks" do
        let(:run_list) { ["local::default"] }

        it "raises an error describing the conflict" do
          expect{policyfile_lock.to_lock}.to raise_error(Solve::Errors::NoSolutionError)
        end

        it "includes the name and location of the included policy in the error message"

        it "includes the source of the conflicting dependency constraint from the including policy" do
          expect{policyfile_lock.to_lock}.to raise_error(Solve::Errors::NoSolutionError) do |e|
            expect(e.to_s).to match(/`cookbookC \(= 2.0.0\)`/) # This one comes from the included policy
            expect(e.to_s).to match(/`cookbookC \(= 1.0.0\)` required by `local-1.0.0`/) # This one comes from the included policy
          end
        end

        it "should not have an open constraint on cookbookC" do
          pending("I think this is a bug")
          expect{policyfile_lock.to_lock}.to raise_error(Solve::Errors::NoSolutionError) do |e|
            expect(e.to_s).not_to match(/`cookbookC \(>= 0.0.0\)`/) # This one comes from the included policy
          end
        end

      end

      context "and the including policy explicitly sets the source for a cookbook which conflicts with the source in the included policy" do

        it "raises an error describing the conflict"

        it "includes the name and location of the included policy in the error message"

      end

    end

    context "when the included policy does not have attributes that conflict with the including policy" do

      it "emits a lockfile with the attributes from both merged"

    end

    context "when the included policy has attributes that conflict with the including policy's attributes" do

      it "raises an error describing all attribute conflicts"

      it "includes the name and location of the included policy in the error message"

      it "includes the source location of the conflicting attribute in the including policy"

    end

  end

  context "when several policies are included" do

    context "when no cookbooks are shared as dependencies or transitive dependencies by included policies" do

      it "does not raise a have conflicting dependency requirements error"

      it "emits a lockfile where cookbooks pulled from the upstreams are at identical versions"

      it "solves the dependencies added by the top-level policyfile"

    end

    context "when some cookbooks appear as dependencies or transitive dependencies of some included policies" do

      context "and the locked versions of the cookbooks match" do

        it "solves the dependencies with the matching versions"

      end

      context "and the locked versions of the cookbooks do not match" do

        it "raises an error describing the conflict"

        it "includes the name and location of the conflicting included policies in the error message"

      end

    end

    context "when the included policies do not have conflicting attributes" do

      it "emits a lockfile with the included policies' attributes merged"

    end

    context "when the included policies have conflicting attributes" do

      it "raises an error describing the conflict"

      it "includes the name an location of the conflicting included policies in the error message"

    end

  end

end


