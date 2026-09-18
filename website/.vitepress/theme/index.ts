import DefaultTheme from "vitepress/theme";
import Home from "./Home.vue";
import FeatureExplorer from "./FeatureExplorer.vue";
import WorkflowDemo from "./WorkflowDemo.vue";
import "./style.css";

export default {
  extends: DefaultTheme,
  enhanceApp({ app }) {
    app.component("ProductHome", Home);
    app.component("FeatureExplorer", FeatureExplorer);
    app.component("WorkflowDemo", WorkflowDemo);
  },
};
