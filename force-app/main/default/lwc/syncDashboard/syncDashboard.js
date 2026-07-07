import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSyncStats from '@salesforce/apex/SyncDashboardController.getSyncStats';
import getPendingConflicts from '@salesforce/apex/SyncDashboardController.getPendingConflicts';
import resolveConflict from '@salesforce/apex/SyncDashboardController.resolveConflict';
import triggerSync from '@salesforce/apex/SyncDashboardController.triggerSync';
import getRecentAuditLog from '@salesforce/apex/SyncDashboardController.getRecentAuditLog';

export default class SyncDashboard extends LightningElement {
  @track syncStats = {};
  @track pendingConflicts = [];
  @track auditLogs = [];
  @track isLoading = false;
  @track isTriggering = false;
  conflictCount = 0;

  connectedCallback() {
    this.loadDashboardData();
    // Refresh every 30 seconds
    setInterval(() => {
      this.loadDashboardData();
    }, 30000);
  }

  loadDashboardData() {
    this.isLoading = true;
    Promise.all([
      this.loadSyncStats(),
      this.loadPendingConflicts(),
      this.loadAuditLog()
    ]).finally(() => {
      this.isLoading = false;
    });
  }

  loadSyncStats() {
    return getSyncStats()
      .then((result) => {
        this.syncStats = result;
      })
      .catch((error) => {
        this.showError('Error loading sync stats', error);
      });
  }

  loadPendingConflicts() {
    return getPendingConflicts({ limitRows: 50 })
      .then((result) => {
        this.pendingConflicts = result;
        this.conflictCount = result ? result.length : 0;
      })
      .catch((error) => {
        this.showError('Error loading pending conflicts', error);
      });
  }

  loadAuditLog() {
    return getRecentAuditLog({ limitRows: 50 })
      .then((result) => {
        this.auditLogs = result;
      })
      .catch((error) => {
        this.showError('Error loading audit log', error);
      });
  }

  handleTriggerSync() {
    this.isTriggering = true;
    triggerSync({ strategy: 'FieldPriority' })
      .then((batchId) => {
        this.showSuccess('Sync Started', `Batch job ${batchId} has been queued`);
        this.loadDashboardData();
      })
      .catch((error) => {
        this.showError('Error triggering sync', error);
      })
      .finally(() => {
        this.isTriggering = false;
      });
  }

  handleResolveConflict(event) {
    const conflictId = event.currentTarget.dataset.conflictId;
    const winningOrg = event.detail.value;

    resolveConflict({ auditLogId: conflictId, winningOrg: winningOrg })
      .then((result) => {
        this.showSuccess(
          'Conflict Resolved',
          `Conflict resolved in favor of ${winningOrg}`
        );
        this.loadDashboardData();
      })
      .catch((error) => {
        this.showError('Error resolving conflict', error);
      });
  }

  handleViewDetails(event) {
    const conflictId = event.currentTarget.dataset.conflictId;
    const conflict = this.pendingConflicts.find(c => c.auditLogId === conflictId);

    if (conflict) {
      this.showInfo(
        `${conflict.objectApiName} - ${conflict.fieldName}`,
        `Record: ${conflict.recordId}\nOrg A: ${conflict.orgAValue}\nOrg B: ${conflict.orgBValue}`
      );
    }
  }

  handleRefresh() {
    this.loadDashboardData();
    this.showSuccess('Dashboard Refreshed', 'Sync data has been updated');
  }

  showSuccess(title, message) {
    this.dispatchEvent(
      new ShowToastEvent({
        title: title,
        message: message,
        variant: 'success',
        mode: 'dismissable'
      })
    );
  }

  showError(title, error) {
    let message = 'Unknown error';
    if (error) {
      if (Array.isArray(error.body)) {
        message = error.body.map(e => e.message).join(', ');
      } else if (typeof error.body === 'object') {
        message = error.body.message;
      } else if (typeof error === 'string') {
        message = error;
      }
    }

    this.dispatchEvent(
      new ShowToastEvent({
        title: title,
        message: message,
        variant: 'error',
        mode: 'sticky'
      })
    );
  }

  showInfo(title, message) {
    this.dispatchEvent(
      new ShowToastEvent({
        title: title,
        message: message,
        variant: 'info',
        mode: 'dismissable'
      })
    );
  }

  get hasPendingConflicts() {
    return this.pendingConflicts && this.pendingConflicts.length > 0;
  }

  get hasAuditLogs() {
    return this.auditLogs && this.auditLogs.length > 0;
  }
}
