# ShopEasy - one-page Java e-commerce on Azure App Service

- `src/` Spring Boot 3 (Java 17) app; the page is `src/main/resources/static/index.html`
- `.github/workflows/ci-cd.yml` GitHub Actions build + deploy
- `azure-pipelines.yml` Azure DevOps build + deploy
- `infra/` Terraform: VNet, public/private subnets, Application Gateway, private endpoint, App Service

Run locally: `mvn spring-boot:run` then open http://localhost:8080
