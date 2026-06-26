import React from 'react';
import ReactDOM from 'react-dom/client';
import { HashRouter } from 'react-router-dom';
import App from './App.jsx';
import { TimezoneProvider } from './components/TimezoneContext.jsx';
import './styles.css';

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <HashRouter>
      <TimezoneProvider>
        <App />
      </TimezoneProvider>
    </HashRouter>
  </React.StrictMode>
);
