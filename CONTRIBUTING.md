# Checklist for contributing
This module has grown over time based on a range of contributions from
people using it. If you follow these contributing guidelines your patch
will likely make it into a release a little quicker.
Please note that this project is released with a Contributor Code of Conduct. By participating in this project you agree to abide by its terms. [Contributor Code of Conduct](code_of_conduct.md).

---

## Short version
+ Commits:
    - Make commits of logical units
    - Check for unnecessary whitespace with "git diff --check" before committing
    - Commit using Unix line endings (check the settings around "crlf" in git-config(1))
    - Do not check in commented out code or unneeded files
    - The first line of the commit message should be a short description (50 characters is the soft limit)
    - The body should provide a meaningful commit message, which:
        - uses the imperative, present tense: "change", not "changed" or "changes"
        - includes motivation for the change, and contrasts its implementation with the previous behavior
        - Make sure that you have tests for the bug you are fixing, or feature you are adding
        - Make sure the test suites passes after your commit (if such a suite exists)
    - When introducing a new feature, make sure it is properly documented in the README.md
    - Add yourself to the Contributors list in the README.md and README_DE.md
+ Submission:
    + Pre-requisites:
        + Make sure you have a [GitHub account](https://github.com/join)
    + Preferred method:
        - Fork the repository on GitHub
        - Push your changes to a topic branch in your fork of the repository. (the format short_description_of_change is usually preferred for this project)
        - Submit a pull request to the repository
        - Rebase your stuff if you've multiple commits for one feature
        - Please only submit multiple features in one branch if they are directly related
    + Preferred for people with repo access:
        - Don't fork the module, create a feature branch
        - Everything else that is mentioned above

---

## Long version
### Make separate commits for logically separate changes.
Please break your commits down into logically consistent units which include new or changed tests relevant to the rest of the change. The goal of doing this is to make the diff easier to read for whoever is reviewing your code.  In general, the easier your diff is to read, the more likely someone will be happy to review it and get it into the code base. If you are going to refactor a piece of code, please do so as a separate commit from your feature or bug fix changes. We also really appreciate changes that include tests to make sure the bug is not re-introduced, and that the feature is not accidentally broken. Describe the technical detail of the change(s). If your description starts to get too long, that is a good sign that you probably need to split up your commit into more finely grained pieces. Commits which plainly describe the things which help reviewers check the patch and future developers understand the  code are much more likely to be merged in with a minimum of bike-shedding or requested changes.  Ideally, the commit message would include information, and be in a form suitable for inclusion in the release notes for the version of Puppet that includes them. Please also check that you are not introducing any trailing whitespace or other "whitespace errors".  You can do this by running "git diff --check" on your changes before you commit.

### Sending your patches
 To submit your changes via a GitHub pull request, we _highly_ recommend that you have them on a topic branch, instead of directly on "master". It makes things much easier to keep track of, especially if you decide to work on another thing before your first change is merged in. GitHub has some pretty good [general documentation](http://help.github.com/) on using their site.  They also have documentation on [creating pull requests](http://help.github.com/send-pull-requests/). In general, after pushing your topic branch up to your repository on GitHub, you can switch to the branch in the GitHub UI and click "Pull Request" towards the top of the page in order to open a pull request.

### Update the related GitHub issue.
If there is a GitHub issue associated with the change you submitted, then you should update the ticket to include the location of your branch, along with any other commentary you may wish to make.

This guide is based on the CONTRIBUTING.md from Puppetlabs Inc and Vox Pupuli.
