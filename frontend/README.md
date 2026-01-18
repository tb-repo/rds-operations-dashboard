# RDS Operations Dashboard - Frontend

React-based frontend dashboard for monitoring and managing RDS instances across multiple AWS accounts.

## Features

- **Dashboard Overview**: Summary cards, charts, and recent alerts
- **Instance List**: Searchable and filterable list of all RDS instances
- **Instance Detail**: Detailed metrics, performance charts, and self-service operations
- **Cost Analysis**: Cost breakdown, optimization recommendations, and trends
- **Compliance Dashboard**: Compliance status, violations, and remediation guidance

## Tech Stack

- **React 18** with TypeScript
- **Vite** for fast development and building
- **Tailwind CSS** for styling
- **React Router** for navigation
- **TanStack Query** (React Query) for data fetching and caching
- **Axios** for API communication
- **Recharts** for data visualization
- **Lucide React** for icons

## Getting Started

### Prerequisites

- Node.js 18+ and npm
- API Gateway URL and API Key from backend deployment

### Installation

1. Install dependencies:
```bash
npm install
```

2. Create `.env` file from example:
```bash
cp .env.example .env
```

3. Update `.env` with your API Gateway details:
```
VITE_API_BASE_URL=https://your-api-gateway-url.execute-api.ap-southeast-1.amazonaws.com
VITE_API_KEY=your-api-key-here
```

### Development

Start the development server:
```bash
npm run dev
```

The app will be available at `http://localhost:3000`

### Build for Production

Build the production bundle:
```bash
npm run build
```

The output will be in the `dist/` directory.

Preview the production build:
```bash
npm run preview
```

## Project Structure

```
frontend/
├── src/
│   ├── components/       # Reusable UI components
│   │   ├── Layout.tsx
│   │   ├── LoadingSpinner.tsx
│   │   ├── ErrorMessage.tsx
│   │   ├── StatusBadge.tsx
│   │   └── StatCard.tsx
│   ├── pages/           # Page components
│   │   ├── Dashboard.tsx
│   │   ├── InstanceList.tsx
│   │   ├── InstanceDetail.tsx
│   │   ├── CostDashboard.tsx
│   │   └── ComplianceDashboard.tsx
│   ├── lib/             # Utilities and API client
│   │   └── api.ts
│   ├── App.tsx          # Main app component with routing
│   ├── main.tsx         # Entry point
│   └── index.css        # Global styles
├── public/              # Static assets
├── index.html           # HTML template
├── package.json
├── tsconfig.json
├── vite.config.ts
└── tailwind.config.js
```

## API Integration

The frontend communicates with the backend API Gateway using Axios. All API calls are defined in `src/lib/api.ts`.

### API Endpoints

- `GET /instances` - List all RDS instances with optional filters
- `GET /instances/:id` - Get instance details
- `GET /health` - Get health metrics
- `GET /health/:instanceId` - Get health metrics for specific instance
- `GET /alerts` - Get all alerts
- `GET /alerts/:instanceId` - Get alerts for specific instance
- `GET /costs` - Get cost data
- `GET /costs/recommendations` - Get cost optimization recommendations
- `GET /compliance` - Get compliance checks
- `GET /compliance/:instanceId` - Get compliance for specific instance
- `POST /operations` - Execute self-service operation
- `POST /cloudops-request` - Generate CloudOps request

### Error Handling

The app includes comprehensive error handling:
- Network errors are caught and displayed to users
- Failed requests can be retried
- Loading states are shown during data fetching
- React Query automatically retries failed requests

### Data Caching

React Query provides automatic caching with:
- 5-minute stale time for all queries
- Automatic refetching on window focus disabled
- Manual refresh via "Refresh" button in header
- Optimistic updates for mutations

## Deployment to S3 + CloudFront

### Manual Deployment

1. Build the production bundle:
```bash
npm run build
```

2. Create S3 bucket for static hosting:
```bash
aws s3 mb s3://rds-dashboard-frontend --region ap-southeast-1
aws s3 website s3://rds-dashboard-frontend --index-document index.html
```

3. Upload build files:
```bash
aws s3 sync dist/ s3://rds-dashboard-frontend --delete
```

4. Create CloudFront distribution (optional for HTTPS and CDN):
```bash
# Use AWS Console or CDK to create CloudFront distribution
# pointing to S3 bucket as origin
```

### Automated Deployment (CDK)

The infrastructure stack includes automated deployment:
- S3 bucket with versioning
- CloudFront distribution with HTTPS
- Automatic invalidation on updates
- See `infrastructure/lib/frontend-stack.ts` for details

## Customization

### Styling

The app uses Tailwind CSS. Customize colors and theme in `tailwind.config.js`.

Custom utility classes are defined in `src/index.css`:
- `.card` - Card container
- `.btn-primary` - Primary button
- `.btn-secondary` - Secondary button
- `.badge-*` - Status badges

### Adding New Pages

1. Create page component in `src/pages/`
2. Add route in `src/App.tsx`
3. Add navigation link in `src/components/Layout.tsx`

### Adding New API Endpoints

1. Define TypeScript interface in `src/lib/api.ts`
2. Add API function to `api` object
3. Use with React Query in components

## Performance Optimization

- Code splitting via React Router lazy loading (can be added)
- Image optimization with Vite
- Tree shaking for smaller bundle size
- Gzip compression in production
- CDN caching via CloudFront

## Browser Support

- Chrome (latest)
- Firefox (latest)
- Safari (latest)
- Edge (latest)

## Troubleshooting

### CORS Errors

Ensure API Gateway has CORS enabled for your frontend domain.

### API Key Issues

Verify the API key in `.env` matches the one from API Gateway.

### Build Errors

Clear node_modules and reinstall:
```bash
rm -rf node_modules package-lock.json
npm install
```

## License

Internal use only - [Company Name]
