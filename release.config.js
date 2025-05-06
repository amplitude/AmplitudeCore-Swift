module.exports = {
  "branches": ["main"],
  "plugins": [
    ["@semantic-release/commit-analyzer", {
      "preset": "angular",
      "parserOpts": {
        "noteKeywords": ["BREAKING CHANGE", "BREAKING CHANGES", "BREAKING"]
      }
    }],
    ["@semantic-release/release-notes-generator", {
      "preset": "angular",
    }],
    ["@semantic-release/changelog", {
      "changelogFile": "CHANGELOG.md"
    }],
    [
      "@semantic-release/github", {
        "assets": [
          { "path": "AmplitudeCore.zip" },
        ]
      }],
      [
        "@google/semantic-release-replace-plugin",
        {
          "replacements": [
            {
              "files": ["AmplitudeCore.podspec"],
              "from": "amplitude_core_version = \".*\"",
              "to": "amplitude_core_version = \"${nextRelease.version}\"",
              "results": [
                {
                  "file": "AmplitudeCore.podspec",
                  "hasChanged": true,
                  "numMatches": 1,
                  "numReplacements": 1
                }
              ],
              "countMatches": true
            },
            {
              "files": ["Package.swift", "Package@swift-5.9.swift"],
              "from": "https://github.com/amplitude/AmplitudeCore-Swift/releases/download/v.*/AmplitudeCore.zip",
              "to": "https://github.com/amplitude/AmplitudeCore-Swift/releases/download/v${nextRelease.version}/AmplitudeCore.zip",
              "results": [
                {
                  "file": "Package.swift",
                  "hasChanged": true,
                  "numMatches": 1,
                  "numReplacements": 1
                },
                {
                  "file": "Package@swift-5.9.swift",
                  "hasChanged": true,
                  "numMatches": 1,
                  "numReplacements": 1
                }
              ],
              "countMatches": true
            },
          ]
        }
      ],
      ["@semantic-release/exec", {
        "prepareCmd": "cat docs/Carthage/AmplitudeCore.json | jq --arg RELEASE '${nextRelease.version}' '. + {$RELEASE: \"https://github.com/amplitude/AmplitudeCore-Swift/releases/download/v\\($RELEASE)/AmplitudeCore.zip\"}' | tee docs/Carthage/AmplitudeCore.json"
      }],
      ["@semantic-release/git", {
        "assets": ["AmplitudeCore.podspec", "CHANGELOG.md", "Package.swift", "Package@swift-5.9.swift", "docs/Carthage/AmplitudeCore.json"],
        "message": "chore(release): ${nextRelease.version} [skip ci]\n\n${nextRelease.notes}"
      }],
       ["@semantic-release/exec", {
         "publishCmd": "pod trunk push AmplitudeCore.podspec",
       }],
    ],
  }
