# Notes for build

**Build Number**: {{buildDetails.buildNumber}}
**Build Requested by**: {{lookup buildDetails.requestedBy 'displayName'}}

# Pull Requests

{{#forEach pullRequests}}

- **{{this.pullRequestId}}** {{this.title}}

  {{/forEach}}

# User Stories

{{#forEach workItems}}

- [**{{this.id}}**]({{#with (lookup this._links 'html')}} {{href}} {{/with}}) {{lookup this.fields 'System.Title'}} (**Assigned** {{#with (lookup this.fields 'System.AssignedTo')}} {{displayName}} {{/with}})

{{/forEach}}
