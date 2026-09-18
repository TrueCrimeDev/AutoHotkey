import DefaultTheme from "vitepress/theme";
import Home from "./Home.vue";
import FeatureExplorer from "./FeatureExplorer.vue";
import WorkflowDemo from "./WorkflowDemo.vue";
import StdoutDemo from "./LineOutDemo.vue";
import ErrorFeedbackDemo from "./ErrorFeedbackDemo.vue";
import "./style.css";

export default {
  extends: DefaultTheme,
  enhanceApp({ app }) {
    app.component("ProductHome", Home);
    app.component("FeatureExplorer", FeatureExplorer);
    app.component("WorkflowDemo", WorkflowDemo);
    app.component("StdoutDemo", StdoutDemo);
    app.component("ErrorFeedbackDemo", ErrorFeedbackDemo);
  },
};
